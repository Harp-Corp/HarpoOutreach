import Foundation

class GmailService {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Email senden
    func sendEmail(to: String, from: String, subject: String, body: String) async throws -> String {
        let token = try await authService.getAccessToken()
        print("[Gmail] Sende Email an \(to) von \(from)")
        let rawEmail = buildMimeEmail(to: to, from: from, subject: subject, body: body)

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
            print("[Gmail] 401 - Token-Refresh...")
            let freshToken = try await authService.getAccessToken()
            let retryResult = try await executeGmailSend(jsonData: jsonData, token: freshToken)
            switch retryResult {
            case .success(let data):
                return parseMessageId(from: data)
            case .needsRetry:
                await MainActor.run { authService.logout() }
                throw GmailError.authExpired
            case .failure(let error): throw error
            }
        case .failure(let error): throw error
        }
    }

    // MARK: - Gmail API Ausfuehrung
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
            await MainActor.run { authService.invalidateAccessToken() }
            return .needsRetry
        case 403: return .failure(.sendFailed("Keine Berechtigung. Pruefe Gmail API Scopes."))
        case 429: return .failure(.sendFailed("Rate Limit erreicht."))
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

    // MARK: - Antworten pruefen
    func checkReplies(sentSubjects: [String]) async throws -> [GmailMessage] {
        let token = try await authService.getAccessToken()
        var allReplies: [GmailMessage] = []
        var seenIds = Set<String>()

        for subject in sentSubjects {
            let cleanSubject = subject
                .replacingOccurrences(of: "Re: ", with: "")
                .replacingOccurrences(of: "RE: ", with: "")
                .replacingOccurrences(of: "Aw: ", with: "")
                .replacingOccurrences(of: "AW: ", with: "")
                .replacingOccurrences(of: "Fwd: ", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanSubject.isEmpty else { continue }

            // Wichtig: Subject in Anfuehrungszeichen fuer exakte Suche
            let quotedSubject = "\"" + cleanSubject + "\""
            let query = "in:inbox subject:\(quotedSubject) -from:me newer_than:90d"

            var components = URLComponents(string: "\(baseURL)/messages")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "10")
            ]

            guard let url = components.url else {
                print("[Gmail] Ungueltige URL fuer Subject: \(cleanSubject)")
                continue
            }

            print("[Gmail] Suche Antworten mit Query: \(query)")

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                print("[Gmail] checkReplies HTTP \(http.statusCode): \(errBody.prefix(300))")
                if http.statusCode == 401 {
                    // Token refresh und nochmal versuchen
                    let freshToken = try await authService.getAccessToken()
                    var retryRequest = URLRequest(url: url)
                    retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResp) = try await URLSession.shared.data(for: retryRequest)
                    if let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode != 200 {
                        print("[Gmail] checkReplies Retry fehlgeschlagen: \(retryHttp.statusCode)")
                        continue
                    }
                    // Parse retry data
                    guard let retryJson = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any],
                          let retryMessages = retryJson["messages"] as? [[String: Any]] else {
                        continue
                    }
                    for msg in retryMessages {
                        guard let msgId = msg["id"] as? String, !seenIds.contains(msgId) else { continue }
                        seenIds.insert(msgId)
                        if let detail = try? await fetchMessage(id: msgId, token: freshToken) {
                            let fromLower = detail.from.lowercased()
                            if fromLower.contains("mf@harpocrates-corp.com") { continue }
                            allReplies.append(detail)
                            print("[Gmail] Antwort von: \(detail.from)")
                        }
                    }
                }
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else {
                print("[Gmail] Keine Antworten fuer: \(cleanSubject)")
                continue
            }

            print("[Gmail] \(messages.count) Nachrichten gefunden fuer: \(cleanSubject)")

            for msg in messages {
                guard let msgId = msg["id"] as? String, !seenIds.contains(msgId) else { continue }
                seenIds.insert(msgId)

                if let detail = try? await fetchMessage(id: msgId, token: token) {
                    let fromLower = detail.from.lowercased()
                    if fromLower.contains("mf@harpocrates-corp.com") { continue }
                    allReplies.append(detail)
                    print("[Gmail] Antwort von: \(detail.from)")
                }
            }
        }

        // Fallback: Suche auch generisch nach allen Inbox-Antworten der letzten 90 Tage
        if allReplies.isEmpty {
            print("[Gmail] Kein Subject-Match - versuche generische Inbox-Suche...")
            let fallbackQuery = "in:inbox -from:me newer_than:30d"
            var components = URLComponents(string: "\(baseURL)/messages")!
            components.queryItems = [
                URLQueryItem(name: "q", value: fallbackQuery),
                URLQueryItem(name: "maxResults", value: "20")
            ]
            if let url = components.url {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let messages = json["messages"] as? [[String: Any]] {
                    print("[Gmail] Fallback: \(messages.count) Inbox-Nachrichten")
                    for msg in messages.prefix(20) {
                        guard let msgId = msg["id"] as? String, !seenIds.contains(msgId) else { continue }
                        seenIds.insert(msgId)
                        if let detail = try? await fetchMessage(id: msgId, token: token) {
                            let fromLower = detail.from.lowercased()
                            if fromLower.contains("mf@harpocrates-corp.com") { continue }
                            allReplies.append(detail)
                        }
                    }
                }
            }
        }

        print("[Gmail] Total: \(allReplies.count) Antworten")
        return allReplies
    }

    // MARK: - Nachricht abrufen
    private func fetchMessage(id: String, token: String) async throws -> GmailMessage {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages/\(id)?format=full")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GmailError.parseFailed
        }

        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: String]] ?? []

        var from = "", subject = "", date = ""
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
                if let mime = part["mimeType"] as? String, mime == "text/plain",
                   let bd = part["body"] as? [String: Any],
                   let b64 = bd["data"] as? String {
                    let padded = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: padded),
                       let text = String(data: decoded, encoding: .utf8) {
                        body = text
                    }
                }
            }
        } else if let bd = payload["body"] as? [String: Any],
                  let b64 = bd["data"] as? String {
            let padded = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let decoded = Data(base64Encoded: padded),
               let text = String(data: decoded, encoding: .utf8) {
                body = text
            }
        }

        return GmailMessage(id: id, from: from, subject: subject, date: date, snippet: snippet, body: body)
    }

    // MARK: - MIME Email mit professioneller Visitenkarte
    private func buildMimeEmail(to: String, from: String, subject: String, body: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let boundary = "HarpoMIME_\(UUID().uuidString)"

        // Body-Text in HTML-Paragraphen
        let htmlParagraphs = body
            .components(separatedBy: "\n\n")
            .map { p in
                let lines = p.components(separatedBy: "\n").joined(separator: "<br>")
                return "<p style=\"margin:0 0 12px 0;line-height:1.6;color:#333333;font-size:14px;\">\(lines)</p>"
            }
            .joined(separator: "\n")

        // Professionelle HTML-Visitenkarte
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"></head>
        <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
        \(htmlParagraphs)
        <table cellpadding="0" cellspacing="0" border="0" style="margin-top:30px;border-top:2px solid #1a365d;padding-top:16px;width:100%;">
        <tr>
        <td style="vertical-align:top;padding-right:16px;width:4px;">
        <div style="width:4px;height:70px;background:#1a365d;border-radius:2px;"></div>
        </td>
        <td style="vertical-align:top;">
        <table cellpadding="0" cellspacing="0" border="0">
        <tr><td style="font-size:16px;font-weight:bold;color:#1a365d;padding-bottom:2px;font-family:Arial,Helvetica,sans-serif;">Martin F\u{00F6}rster</td></tr>
        <tr><td style="font-size:12px;color:#4a5568;padding-bottom:8px;font-family:Arial,Helvetica,sans-serif;">CEO & Founder</td></tr>
        <tr><td style="font-size:13px;font-weight:bold;color:#2d3748;padding-bottom:8px;font-family:Arial,Helvetica,sans-serif;">Harpocrates Solutions GmbH</td></tr>
        <tr><td style="font-size:12px;color:#4a5568;line-height:1.8;font-family:Arial,Helvetica,sans-serif;">
        \u{260E} +49 172 6348377<br>
        \u{2709} <a href="mailto:mf@harpocrates-corp.com" style="color:#2b6cb0;text-decoration:none;">mf@harpocrates-corp.com</a><br>
        \u{1F310} <a href="https://www.harpocrates-corp.com" style="color:#2b6cb0;text-decoration:none;">www.harpocrates-corp.com</a><br>
        \u{1F4CD} Berlin, Germany
        </td></tr>
        </table>
        </td>
        </tr>
        </table>
        <p style="margin-top:24px;font-size:10px;color:#a0aec0;font-family:Arial,Helvetica,sans-serif;">
        <a href="mailto:mf@harpocrates-corp.com?subject=Unsubscribe&body=Bitte%20entfernen%20Sie%20mich%20von%20Ihrer%20Mailingliste." style="color:#a0aec0;text-decoration:underline;">Abmelden / Unsubscribe</a>
        </p>
        </div>
        </body>
        </html>
        """

        let plainB64 = Data(body.utf8).base64EncodedString()
        let htmlB64 = Data(html.utf8).base64EncodedString()

        // MIME-Nachricht OHNE fuehrende Leerzeichen bei Headern
        var mime = "From: Martin Foerster <\(from)>\r\n"
        mime += "To: \(to)\r\n"
        mime += "Subject: \(encodedSubject)\r\n"
        mime += "MIME-Version: 1.0\r\n"
        mime += "Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n"
        mime += "\r\n"
        mime += "--\(boundary)\r\n"
        mime += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
        mime += "Content-Transfer-Encoding: base64\r\n"
        mime += "\r\n"
        mime += "\(plainB64)\r\n"
        mime += "--\(boundary)\r\n"
        mime += "Content-Type: text/html; charset=\"UTF-8\"\r\n"
        mime += "Content-Transfer-Encoding: base64\r\n"
        mime += "\r\n"
        mime += "\(htmlB64)\r\n"
        mime += "--\(boundary)--"

        return mime
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
            case .sendFailed(let msg): return "Email senden fehlgeschlagen: \(String(msg.prefix(200)))"
            case .authExpired: return "Google-Anmeldung abgelaufen. Bitte erneut anmelden."
            case .parseFailed: return "Gmail Nachricht konnte nicht gelesen werden"
            }
        }
    }
}
