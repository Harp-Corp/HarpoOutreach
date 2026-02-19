import Foundation

class GmailService {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Email senden (HTML Format mit Footer + Logo + Unsubscribe)
    func sendEmail(to: String, from: String, subject: String,
                   body: String) async throws -> String {
        let token = try await authService.getAccessToken()
        print("[Gmail] Sende Email an \(to) von \(from)")

        let rawEmail = buildHtmlEmail(to: to, from: from,
                                      subject: subject, body: body)
        let base64Email = rawEmail
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload: [String: String] = ["raw": base64Email]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        let result = try await executeGmailSend(jsonData: jsonData, token: token)
        switch result {
        case .success(let data):
            return parseMessageId(from: data)
        case .needsRetry:
            print("[Gmail] 401 erhalten - versuche Token-Refresh und Retry...")
            let freshToken = try await authService.getAccessToken()
            let retryResult = try await executeGmailSend(jsonData: jsonData, token: freshToken)
            switch retryResult {
            case .success(let data):
                print("[Gmail] Retry erfolgreich!")
                return parseMessageId(from: data)
            case .needsRetry:
                print("[Gmail] Retry ebenfalls 401 - Logout wird erzwungen")
                await MainActor.run { authService.logout() }
                throw GmailError.authExpired
            case .failure(let error): throw error
            }
        case .failure(let error): throw error
        }
    }

    // MARK: - Gmail API Request ausfuehren
    private enum SendResult {
        case success(Data)
        case needsRetry
        case failure(GmailError)
    }

    private func executeGmailSend(jsonData: Data, token: String) async throws -> SendResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .failure(.sendFailed("Keine HTTP Response"))
        }

        switch http.statusCode {
        case 200: return .success(data)
        case 401:
            let errBody = String(data: data, encoding: .utf8) ?? ""
            print("[Gmail] 401 Unauthorized: \(errBody.prefix(200))")
            await MainActor.run { authService.invalidateAccessToken() }
            return .needsRetry
        case 403:
            return .failure(.sendFailed("Keine Berechtigung. Pruefe Gmail API Scopes."))
        case 429:
            return .failure(.sendFailed("Rate Limit erreicht."))
        default:
            let errBody = String(data: data, encoding: .utf8) ?? ""
            return .failure(.sendFailed("HTTP \(http.statusCode): \(String(errBody.prefix(200)))"))
        }
    }

    private func parseMessageId(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messageId = json["id"] as? String {
            print("[Gmail] Email gesendet, ID: \(messageId)")
            return messageId
        }
        return "sent"
    }

    // MARK: - Antworten pruefen (Subject-basiert)
    func checkReplies(sentSubjects: [String]) async throws -> [GmailMessage] {
        let token = try await authService.getAccessToken()
        var allReplies: [GmailMessage] = []
        var seenIds = Set<String>()

        for subject in sentSubjects {
            let cleanSubject = subject
                .replacingOccurrences(of: "Re: ", with: "")
                .replacingOccurrences(of: "RE: ", with: "")
                .replacingOccurrences(of: "Fwd: ", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanSubject.isEmpty else { continue }

            let query = "in:inbox subject:\"\(cleanSubject)\" newer_than:30d"
            let encodedQuery = query.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlStr = "\(baseURL)/messages?q=\(encodedQuery)&maxResults=10"

            print("[Gmail] Suche Antworten mit Subject: \(cleanSubject)")

            var request = URLRequest(url: URL(string: urlStr)!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                print("[Gmail] checkReplies HTTP \(http.statusCode): \(errBody.prefix(200))")
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else {
                print("[Gmail] Keine Antworten fuer Subject: \(cleanSubject)")
                continue
            }

            print("[Gmail] \(messages.count) Nachrichten fuer Subject: \(cleanSubject)")

            for msg in messages {
                guard let msgId = msg["id"] as? String else { continue }
                guard !seenIds.contains(msgId) else { continue }
                seenIds.insert(msgId)

                if let detail = try? await fetchMessage(id: msgId, token: token) {
                    let subjectLower = detail.subject.lowercased()
                    if subjectLower.contains("re:") || subjectLower.contains("aw:") {
                        allReplies.append(detail)
                    }
                }
            }
        }

        print("[Gmail] Insgesamt \(allReplies.count) echte Antworten gefunden")
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
        var body = snippet

        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if let mimeType = part["mimeType"] as? String,
                   mimeType == "text/plain",
                   let bodyData = part["body"] as? [String: Any],
                   let b64 = bodyData["data"] as? String {
                    let padded = b64.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: padded),
                       let text = String(data: decoded, encoding: .utf8) {
                        body = text
                    }
                }
            }
        } else if let bodyObj = payload["body"] as? [String: Any],
                  let b64 = bodyObj["data"] as? String {
            let padded = b64.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            if let decoded = Data(base64Encoded: padded),
               let text = String(data: decoded, encoding: .utf8) {
                body = text
            }
        }

        return GmailMessage(id: id, from: from, subject: subject, date: date, snippet: snippet, body: body)
    }

    // MARK: - Professionelle HTML Email bauen (RFC 2822 MIME)
    private func buildHtmlEmail(to: String, from: String, subject: String, body: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="

        // Body-Text in HTML Paragraphen umwandeln
        let htmlParagraphs = body
            .components(separatedBy: "\n\n")
            .map { paragraph in
                let lines = paragraph
                    .components(separatedBy: "\n")
                    .joined(separator: "<br>")
                return "<p style=\"margin:0 0 12px 0;line-height:1.6;\">\(lines)</p>"
            }
            .joined(separator: "\n")

        let htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;padding:0;background-color:#f5f5f5;font-family:Arial,Helvetica,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5f5;">
        <tr><td align="center" style="padding:20px 0;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;">

        <!-- Logo Header -->
        <tr><td style="padding:24px 32px 16px 32px;border-bottom:2px solid #1a1a2e;">
        <img src="https://new.harpocrates-corp.com/harpocrates-logo.png" alt="Harpocrates" width="180" style="display:block;max-width:180px;height:auto;">
        </td></tr>

        <!-- Email Body -->
        <tr><td style="padding:32px;color:#333333;font-size:15px;">
        \(htmlParagraphs)
        </td></tr>

        <!-- Footer -->
        <tr><td style="padding:24px 32px;background-color:#1a1a2e;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="color:#ffffff;font-size:13px;line-height:1.8;">
        <strong>Harpocrates Solutions GmbH&reg;</strong><br>
        Berlin | Germany | Mobile: +49 172 6348377<br>
        <a href="mailto:mf@harpocrates-corp.com" style="color:#8cb4ff;text-decoration:none;">mf@harpocrates-corp.com</a><br>
        <a href="https://www.harpocrates-corp.com" style="color:#8cb4ff;text-decoration:none;">www.harpocrates-corp.com</a>
        </td></tr>
        </table>
        </td></tr>

        <!-- Unsubscribe -->
        <tr><td align="center" style="padding:16px 32px;background-color:#f0f0f0;">
        <a href="mailto:mf@harpocrates-corp.com?subject=Unsubscribe&body=Bitte%20entfernen%20Sie%20mich%20von%20Ihrer%20Mailingliste." style="color:#999999;font-size:11px;text-decoration:underline;">Abmelden / Unsubscribe</a>
        </td></tr>

        </table>
        </td></tr>
        </table>
        </body>
        </html>
        """

        let boundary = "HarpoMIME_\(UUID().uuidString)"

        return """
        From: Martin Foerster <\(from)>\r
        To: \(to)\r
        Subject: \(encodedSubject)\r
        MIME-Version: 1.0\r
        Content-Type: multipart/alternative; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: base64\r
        \r
        \(Data(body.utf8).base64EncodedString())\r
        --\(boundary)\r
        Content-Type: text/html; charset="UTF-8"\r
        Content-Transfer-Encoding: base64\r
        \r
        \(Data(htmlBody.utf8).base64EncodedString())\r
        --\(boundary)--
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
                return "Google-Anmeldung abgelaufen. Bitte erneut anmelden."
            case .parseFailed:
                return "Gmail Nachricht konnte nicht gelesen werden"
            }
        }
    }
}
