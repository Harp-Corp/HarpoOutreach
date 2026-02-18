import Foundation

class GmailService {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Email senden (FIX: 401 Handling + Retry)
    func sendEmail(to: String, from: String, subject: String,
                   body: String) async throws -> String {
        let token = try await authService.getAccessToken()
        print("[Gmail] Sende Email an \(to) von \(from)")

        let rawEmail = buildRawEmail(to: to, from: from,
                                     subject: subject, body: body)
        let base64Email = rawEmail
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload: [String: String] = ["raw": base64Email]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(baseURL)/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GmailError.sendFailed("Keine HTTP Response")
        }

        // FIX: Spezifische HTTP-Status Behandlung
        switch http.statusCode {
        case 200:
            break // Erfolg
        case 401:
            let errBody = String(data: data, encoding: .utf8) ?? ""
            print("[Gmail] 401 Unauthorized: \(errBody.prefix(200))")
            // Token ist ungueltig - Logout erzwingen damit User sich neu anmelden muss
            await MainActor.run {
                authService.logout()
            }
            throw GmailError.authExpired
        case 403:
            throw GmailError.sendFailed("Keine Berechtigung. Pruefe Gmail API Scopes in Google Cloud Console.")
        case 429:
            throw GmailError.sendFailed("Rate Limit erreicht. Bitte warte einen Moment.")
        default:
            let errBody = String(data: data, encoding: .utf8) ?? ""
            print("[Gmail] HTTP \(http.statusCode): \(errBody.prefix(200))")
            throw GmailError.sendFailed("HTTP \(http.statusCode): \(String(errBody.prefix(200)))")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messageId = json["id"] as? String {
            print("[Gmail] Email gesendet, ID: \(messageId)")
            return messageId
        }
        return "sent"
    }

    // MARK: - Antworten pruefen
    func checkReplies(sentToEmails: [String]) async throws -> [GmailMessage] {
        let token = try await authService.getAccessToken()

        var allReplies: [GmailMessage] = []

        for email in sentToEmails {
            let query = "from:\(email) is:unread"
            let encodedQuery = query.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlStr = "\(baseURL)/messages?q=\(encodedQuery)&maxResults=10"

            var request = URLRequest(url: URL(string: urlStr)!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]]
            else { continue }

            for msg in messages {
                guard let msgId = msg["id"] as? String else { continue }
                if let detail = try? await fetchMessage(id: msgId, token: token) {
                    allReplies.append(detail)
                }
            }
        }

        return allReplies
    }

    // MARK: - Einzelne Nachricht abrufen
    private func fetchMessage(id: String, token: String) async throws -> GmailMessage {
        let urlStr = "\(baseURL)/messages/\(id)?format=full"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GmailError.parseFailed
        }

        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: String]] ?? []

        var from = ""
        var subject = ""
        var date = ""
        for header in headers {
            switch header["name"]?.lowercased() {
            case "from": from = header["value"] ?? ""
            case "subject": subject = header["value"] ?? ""
            case "date": date = header["value"] ?? ""
            default: break
            }
        }

        let snippet = json["snippet"] as? String ?? ""

        // Body extrahieren
        var body = snippet
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if let mimeType = part["mimeType"] as? String, mimeType == "text/plain",
                   let bodyData = part["body"] as? [String: Any],
                   let b64 = bodyData["data"] as? String {
                    let padded = b64
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: padded),
                       let text = String(data: decoded, encoding: .utf8) {
                        body = text
                    }
                }
            }
        } else if let bodyObj = payload["body"] as? [String: Any],
                  let b64 = bodyObj["data"] as? String {
            let padded = b64
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            if let decoded = Data(base64Encoded: padded),
               let text = String(data: decoded, encoding: .utf8) {
                body = text
            }
        }

        return GmailMessage(id: id, from: from, subject: subject,
                           date: date, snippet: snippet, body: body)
    }

    // MARK: - Raw Email bauen (RFC 2822)
    private func buildRawEmail(to: String, from: String,
                               subject: String, body: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        return """
        From: \(from)\r
        To: \(to)\r
        Subject: \(encodedSubject)\r
        MIME-Version: 1.0\r
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: base64\r
        \r
        \(Data(body.utf8).base64EncodedString())
        """
    }

    // MARK: - Types
    struct GmailMessage: Identifiable, Codable {
        let id: String
        let from: String
        let subject: String
        let date: String
        let snippet: String
        let body: String
    }

    enum GmailError: LocalizedError {
        case sendFailed(String)
        case authExpired
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .sendFailed(let msg):
                return "Email senden fehlgeschlagen: \(String(msg.prefix(200)))"
            case .authExpired:
                return "Google-Anmeldung abgelaufen. Bitte unter Einstellungen erneut mit Google anmelden."
            case .parseFailed:
                return "Gmail Nachricht konnte nicht gelesen werden"
            }
        }
    }
}
