import Foundation
import Combine
import AppKit

class GoogleAuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail = ""
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    
    private var clientID: String = ""
    private var clientSecret: String = ""
    
    private let redirectURI = "http://127.0.0.1:8765/callback"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/userinfo.email"
    ].joined(separator: " ")
    
    private let keychainService = "com.harpocrates.outreach"
    
    // MARK: - Configure
    func configure(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        loadTokens()
    }
    
    // MARK: - Get valid access token (FIX: synchrones Token-Handling)
    func getAccessToken() async throws -> String {
        // 1. Pruefe ob Token noch gueltig
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        
        // 2. Versuche Token zu refreshen
        if let refresh = refreshToken {
            do {
                let newToken = try await refreshAccessTokenAndReturn(refreshToken: refresh)
                return newToken
            } catch {
                print("[GoogleAuth] Token refresh fehlgeschlagen: \(error.localizedDescription)")
                // Refresh Token ungueltig - Logout erzwingen
                await MainActor.run {
                    self.accessToken = nil
                    self.tokenExpiry = nil
                    self.isAuthenticated = false
                }
                throw AuthError.tokenExpired
            }
        }
        
        throw AuthError.notAuthenticated
    }
    
    // MARK: - Invalidate Access Token (damit getAccessToken() neu refresht)
    func invalidateAccessToken() {
        accessToken = nil
        tokenExpiry = nil
        print("[GoogleAuth] Access Token invalidiert - naechster Aufruf wird Token refreshen")
    }
    
    // MARK: - Start OAuth Flow
    func startOAuthFlow() {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            print("Google Client ID/Secret nicht konfiguriert")
            return
        }
        
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        startLocalServer()
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Local HTTP Server for Callback
    private func startLocalServer() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let server = self.createSocket(port: 8765)
            guard server >= 0 else {
                print("Server konnte nicht gestartet werden")
                return
            }
            defer { close(server) }
            
            let client = accept(server, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(client, &buffer, buffer.count)
            guard bytesRead > 0 else { return }
            
            let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            
            let successResponse = """
            HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n
            <html><body><h1>Authentifizierung erfolgreich!</h1><p>Du kannst dieses Fenster schliessen.</p></body></html>
            """
            let _ = successResponse.withCString { ptr in
                write(client, ptr, strlen(ptr))
            }
            
            if let code = self.extractCode(from: request) {
                Task {
                    try? await self.exchangeCodeForTokens(code: code)
                }
            }
        }
    }
    
    private func createSocket(port: UInt16) -> Int32 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return -1 }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else { close(sock); return -1 }
        guard listen(sock, 1) >= 0 else { close(sock); return -1 }
        return sock
    }
    
    private func extractCode(from request: String) -> String? {
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(path)),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        return code
    }
    
    // MARK: - Exchange Code for Tokens
    private func exchangeCodeForTokens(code: String) async throws {
        let params = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        let tokenData = try await postForm(url: tokenURL, params: params)
        try await processTokenResponse(tokenData)
        await fetchUserEmail()
    }
    
    // MARK: - Refresh Token (FIX: gibt neuen Token direkt zurueck)
    private func refreshAccessTokenAndReturn(refreshToken: String) async throws -> String {
        let params = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]
        let tokenData = try await postForm(url: tokenURL, params: params)
        guard let json = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any] else {
            throw AuthError.tokenParseFailed
        }
        if let error = json["error"] as? String {
            let desc = json["error_description"] as? String ?? error
            print("[GoogleAuth] Token error: \(desc)")
            throw AuthError.tokenError(desc)
        }
        guard let newAccess = json["access_token"] as? String, !newAccess.isEmpty else {
            throw AuthError.tokenParseFailed
        }
        let expiresIn = json["expires_in"] as? Int ?? 3600
        let newRefresh = json["refresh_token"] as? String
        // FIX: Synchron auf MainActor setzen und warten
        await MainActor.run {
            self.accessToken = newAccess
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
            if let r = newRefresh { self.refreshToken = r }
            self.isAuthenticated = true
            self.saveTokens()
        }
        print("[GoogleAuth] Token erfolgreich refreshed, expires in \(expiresIn)s")
        return newAccess
    }
    
    // MARK: - Process Token Response (FIX: @MainActor statt DispatchQueue)
    private func processTokenResponse(_ data: Data) async throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenParseFailed
        }
        if let error = json["error"] as? String {
            let desc = json["error_description"] as? String ?? error
            throw AuthError.tokenError(desc)
        }
        let newAccess = json["access_token"] as? String ?? ""
        let expiresIn = json["expires_in"] as? Int ?? 3600
        let newRefresh = json["refresh_token"] as? String
        // FIX: await MainActor.run statt DispatchQueue.main.async
        await MainActor.run {
            self.accessToken = newAccess
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
            if let r = newRefresh { self.refreshToken = r }
            self.isAuthenticated = true
            self.saveTokens()
        }
        print("[GoogleAuth] Tokens gespeichert, authenticated=true")
    }
    
    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            await MainActor.run { self.userEmail = email }
            print("[GoogleAuth] User email: \(email)")
        }
    }
    
    // MARK: - HTTP Helper
    private func postForm(url: String, params: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = params.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
    
    // MARK: - Token Persistence
    private func saveTokens() {
        let dict: [String: String] = [
            "access_token": accessToken ?? "",
            "refresh_token": refreshToken ?? "",
            "expiry": (tokenExpiry ?? Date()).timeIntervalSince1970.description
        ]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "google_tokens")
        }
    }
    
    private func loadTokens() {
        guard let data = UserDefaults.standard.data(forKey: "google_tokens"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        accessToken = dict["access_token"]
        refreshToken = dict["refresh_token"]
        if let exp = dict["expiry"], let ts = Double(exp) {
            tokenExpiry = Date(timeIntervalSince1970: ts)
        }
        if refreshToken != nil && !(refreshToken?.isEmpty ?? true) {
            isAuthenticated = true
        }
        print("[GoogleAuth] Tokens geladen, hasRefresh=\(refreshToken != nil), hasAccess=\(accessToken != nil)")
    }
    
    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        userEmail = ""
        UserDefaults.standard.removeObject(forKey: "google_tokens")
        print("[GoogleAuth] Logout")
    }
    
    enum AuthError: LocalizedError {
        case notAuthenticated
        case tokenExpired
        case tokenParseFailed
        case tokenError(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Nicht authentifiziert. Bitte Google Login durchfuehren."
            case .tokenExpired:
                return "Token abgelaufen. Bitte erneut mit Google anmelden."
            case .tokenParseFailed:
                return "Token-Antwort konnte nicht gelesen werden."
            case .tokenError(let e):
                return "Google Auth Fehler: \(e)"
            }
        }
    }
}
