// HarpoOutreachWeb - Server-side Google OAuth Service
// Handles OAuth flow, token management, Gmail, and Sheets
import Foundation
import Vapor

actor GoogleAuthServiceWeb {
    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/userinfo.email"
    ].joined(separator: " ")

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var userEmail: String = ""
    private let client: Client
    private let logger: Logger

    init(clientID: String, clientSecret: String, serverBaseURL: String, client: Client, logger: Logger) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = serverBaseURL + "/api/v1/auth/callback"
        self.client = client
        self.logger = logger
    }

    // MARK: - OAuth URL
    func getAuthURL() -> String {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url?.absoluteString ?? authURL
    }

    // MARK: - Exchange Code for Tokens
    func exchangeCode(_ code: String) async throws -> String {
        let params = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        let tokenData = try await postForm(params: params)
        guard let json = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any] else {
            throw Abort(.badGateway, reason: "Token parse failed")
        }
        if let error = json["error"] as? String {
            throw Abort(.badGateway, reason: "OAuth error: \(json["error_description"] as? String ?? error)")
        }
        self.accessToken = json["access_token"] as? String
        self.refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? Int ?? 3600
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
        if let token = accessToken { await fetchUserEmail(token: token) }
        logger.info("Google OAuth: tokens received for \(userEmail)")
        return userEmail
    }

    // MARK: - Get Valid Access Token
    func getAccessToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        if let refresh = refreshToken {
            return try await refreshAccessToken(refresh)
        }
        throw Abort(.unauthorized, reason: "Not authenticated. Start OAuth flow at /api/v1/auth/google")
    }

    var isAuthenticated: Bool { accessToken != nil }
    var currentEmail: String { userEmail }

    // MARK: - Refresh Token
    private func refreshAccessToken(_ refresh: String) async throws -> String {
        let params = [
            "refresh_token": refresh,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]
        let data = try await postForm(params: params)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String else {
            self.accessToken = nil
            throw Abort(.unauthorized, reason: "Token refresh failed. Re-authenticate.")
        }
        let expiresIn = json["expires_in"] as? Int ?? 3600
        self.accessToken = newAccess
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
        if let r = json["refresh_token"] as? String { self.refreshToken = r }
        logger.info("Google OAuth: token refreshed")
        return newAccess
    }

    // MARK: - Fetch User Email
    private func fetchUserEmail(token: String) async {
        let uri = URI(string: "https://www.googleapis.com/oauth2/v2/userinfo")
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(token)")
        if let resp = try? await client.get(uri, headers: headers),
           let json = try? resp.content.decode([String: String].self),
           let email = json["email"] {
            self.userEmail = email
        }
    }

    // MARK: - HTTP Form Post
    private func postForm(params: [String: String]) async throws -> Data {
        let uri = URI(string: tokenURL)
        let body = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        let response = try await client.post(uri) { req in
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
            req.body = .init(string: body)
        }
        guard let buffer = response.body else { throw Abort(.badGateway, reason: "Empty token response") }
        return Data(buffer: buffer)
    }
}
