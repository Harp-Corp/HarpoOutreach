import Foundation
import Combine
import AppKit

class LinkedInAuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userName = ""

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var personId: String?

    private var clientID: String = ""
    private var clientSecret: String = ""

    private let authURL = "https://www.linkedin.com/oauth/v2/authorization"
    private let tokenURL = "https://www.linkedin.com/oauth/v2/accessToken"
    private let redirectURI = "http://127.0.0.1:8766/callback"
    private let scopes = "openid profile email w_member_social"

    // MARK: - Configure
    func configure(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        loadTokens()
    }

    // MARK: - Public Accessors
    func getAccessToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date(), !token.isEmpty {
            return token
        }
        if let refresh = refreshToken, !refresh.isEmpty {
            do {
                return try await refreshAccessTokenAndReturn(refreshToken: refresh)
            } catch {
                print("[LinkedInAuth] Token refresh fehlgeschlagen: \(error.localizedDescription)")
                await MainActor.run {
                    self.accessToken = nil
                    self.tokenExpiry = nil
                    self.isAuthenticated = false
                }
                throw LinkedInAuthError.tokenExpired
            }
        }
        throw LinkedInAuthError.notAuthenticated
    }

    func getPersonId() -> String? {
        return personId
    }

    // MARK: - Start OAuth Flow
    func startOAuthFlow() {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            print("[LinkedInAuth] Client ID/Secret nicht konfiguriert")
            return
        }
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        startLocalServer()
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Local HTTP Server
    private func startLocalServer() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let server = self.createSocket(port: 8766)
            guard server >= 0 else {
                print("[LinkedInAuth] Server konnte nicht gestartet werden")
                return
            }
            let client = accept(server, nil, nil)
            guard client >= 0 else { close(server); return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(client, &buffer, buffer.count)
            guard bytesRead > 0 else { close(client); close(server); return }
            let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            if let code = self.extractCode(from: request) {
                let html = """
                HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\
                <html><body style="font-family:-apple-system,sans-serif;text-align:center;padding:60px;">\
                <h2>LinkedIn Authentifizierung erfolgreich!</h2>\
                <p>Du kannst dieses Fenster schliessen.</p>\
                </body></html>
                """
                write(client, html, html.utf8.count)
                close(client)
                close(server)
                let authService = self
                Task {
                    do {
                        try await authService.exchangeCodeForTokens(code: code)
                        print("[LinkedInAuth] Auth komplett, isAuthenticated=\(authService.isAuthenticated)")
                    } catch {
                        print("[LinkedInAuth] Token-Exchange FEHLER: \(error.localizedDescription)")
                        await MainActor.run {
                            authService.isAuthenticated = false
                        }
                    }
                }
            } else {
                let errHtml = """
                HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\
                <html><body><h2>Fehler</h2><p>Kein Code erhalten.</p></body></html>
                """
                write(client, errHtml, errHtml.utf8.count)
                close(client)
                close(server)
            }
        }
    }

    // MARK: - Socket Helper
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
        print("[LinkedInAuth] Token-Exchange gestartet mit Code: \(code.prefix(10))...")
        print("[LinkedInAuth] ClientID: \(clientID.prefix(8))... Secret-Laenge: \(clientSecret.count)")
        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI
        ]
        let tokenData = try await postForm(url: tokenURL, params: params)
        try await processTokenResponse(tokenData)
        await fetchUserProfile()
    }

    // MARK: - Refresh Token
    private func refreshAccessTokenAndReturn(refreshToken: String) async throws -> String {
        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        let tokenData = try await postForm(url: tokenURL, params: params)
        guard let json = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any] else {
            throw LinkedInAuthError.tokenParseFailed
        }
        if let error = json["error"] as? String {
            throw LinkedInAuthError.tokenError(json["error_description"] as? String ?? error)
        }
        guard let newAccess = json["access_token"] as? String, !newAccess.isEmpty else {
            throw LinkedInAuthError.tokenParseFailed
        }
        let expiresIn = json["expires_in"] as? Int ?? 5184000
        let newRefresh = json["refresh_token"] as? String
        await MainActor.run {
            self.accessToken = newAccess
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
            if let r = newRefresh { self.refreshToken = r }
            self.isAuthenticated = true
            self.saveTokens()
        }
        return newAccess
    }

    // MARK: - Process Token Response
    private func processTokenResponse(_ data: Data) async throws {
        if let raw = String(data: data, encoding: .utf8) {
            print("[LinkedInAuth] Token-Response: \(raw.prefix(500))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinkedInAuthError.tokenParseFailed
        }
        if let error = json["error"] as? String {
            let desc = json["error_description"] as? String ?? error
            print("[LinkedInAuth] API Error: \(desc)")
            throw LinkedInAuthError.tokenError(desc)
        }
        guard let newAccess = json["access_token"] as? String, !newAccess.isEmpty else {
            print("[LinkedInAuth] Kein access_token in Response")
            throw LinkedInAuthError.tokenParseFailed
        }
        let expiresIn = json["expires_in"] as? Int ?? 5184000
        let newRefresh = json["refresh_token"] as? String
        await MainActor.run {
            self.accessToken = newAccess
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
            if let r = newRefresh { self.refreshToken = r }
            self.isAuthenticated = true
            self.saveTokens()
        }
        print("[LinkedInAuth] Token gespeichert, expires_in=\(expiresIn)s")
    }

    // MARK: - Fetch User Profile (FIX: extract sub as personId)
    private func fetchUserProfile() async {
        guard let token = accessToken, !token.isEmpty else { return }
        var req = URLRequest(url: URL(string: "https://api.linkedin.com/v2/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, resp) = try? await URLSession.shared.data(for: req) {
            if let http = resp as? HTTPURLResponse {
                print("[LinkedInAuth] UserInfo HTTP \(http.statusCode)")
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let sub = json["sub"] as? String
                let name = (json["name"] as? String) ?? ""
                let given = (json["given_name"] as? String) ?? ""
                let family = (json["family_name"] as? String) ?? ""
                let display = name.isEmpty ? "\(given) \(family)".trimmingCharacters(in: .whitespaces) : name
                print("[LinkedInAuth] PersonId (sub): \(sub ?? "nil"), Name: \(display)")
                await MainActor.run {
                    self.personId = sub
                    self.userName = display.isEmpty ? "LinkedIn verbunden" : display
                    self.saveTokens()
                }
            }
        }
    }

    // MARK: - HTTP Helper (korrektes form-urlencoded Encoding)
    private func formURLEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func postForm(url: String, params: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = params.map { "\(formURLEncode($0.key))=\(formURLEncode($0.value))" }.joined(separator: "&")
        print("[LinkedInAuth] POST body: \(body.prefix(200))")
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let respBody = String(data: data, encoding: .utf8) ?? ""
            print("[LinkedInAuth] HTTP \(http.statusCode): \(respBody.prefix(300))")
            throw LinkedInAuthError.tokenError("HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Token Persistence (inkl. personId)
    private func saveTokens() {
        let dict: [String: String] = [
            "access_token": accessToken ?? "",
            "refresh_token": refreshToken ?? "",
            "expiry": (tokenExpiry ?? Date()).timeIntervalSince1970.description,
            "person_id": personId ?? ""
        ]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "linkedin_tokens")
            UserDefaults.standard.synchronize()
        }
    }

    private func loadTokens() {
        guard let data = UserDefaults.standard.data(forKey: "linkedin_tokens"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            print("[LinkedInAuth] Keine gespeicherten Tokens gefunden")
            return
        }
        accessToken = dict["access_token"]
        refreshToken = dict["refresh_token"]
        personId = dict["person_id"]
        if let exp = dict["expiry"], let ts = Double(exp) { tokenExpiry = Date(timeIntervalSince1970: ts) }
        let hasAccess = accessToken != nil && !(accessToken?.isEmpty ?? true)
        let hasRefresh = refreshToken != nil && !(refreshToken?.isEmpty ?? true)
        let notExpired = tokenExpiry.map { $0 > Date() } ?? false
        isAuthenticated = (hasAccess && notExpired) || hasRefresh
        print("[LinkedInAuth] loadTokens: authenticated=\(isAuthenticated), hasAccess=\(hasAccess), notExpired=\(notExpired), personId=\(personId ?? "nil")")
    }

    func logout() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil; personId = nil
        isAuthenticated = false; userName = ""
        UserDefaults.standard.removeObject(forKey: "linkedin_tokens")
    }

    // MARK: - Errors
    enum LinkedInAuthError: LocalizedError {
        case notAuthenticated, tokenExpired, tokenParseFailed, tokenError(String)
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Nicht bei LinkedIn angemeldet. Bitte LinkedIn verbinden."
            case .tokenExpired: return "LinkedIn Token abgelaufen."
            case .tokenParseFailed: return "Token-Antwort konnte nicht gelesen werden."
            case .tokenError(let e): return "LinkedIn: \(e)"
            }
        }
    }
}
