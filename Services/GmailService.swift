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

    // MARK: - Antworten pruefen (Subject + Lead-Email Fallback)
    func checkReplies(sentSubjects: [String], leadEmails: [String] = []) async throws -> [GmailMessage] {
        let token = try await authService.getAccessToken()
        var allReplies: [GmailMessage] = []
        var seenIds = Set<String>()

        // 1. Subject-basierte Suche
        for subject in sentSubjects {
            let cleanSubject = subject
                .replacingOccurrences(of: "Re: ", with: "")
                .replacingOccurrences(of: "RE: ", with: "")
                .replacingOccurrences(of: "Aw: ", with: "")
                .replacingOccurrences(of: "AW: ", with: "")
                .replacingOccurrences(of: "Fwd: ", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanSubject.isEmpty else { continue }

            let quotedSubject = "\"" + cleanSubject + "\""
            let query = "subject:\(quotedSubject) -from:me newer_than:90d"

            let msgs = try await searchGmail(query: query, token: token, maxResults: 10)
            for msg in msgs {
                guard !seenIds.contains(msg.id) else { continue }
                seenIds.insert(msg.id)
                let fromLower = msg.from.lowercased()
                if fromLower.contains("mf@harpocrates-corp.com") { continue }
                allReplies.append(msg)
                print("[Gmail] Subject-Match Antwort von: \(msg.from)")
            }
        }

        // 2. Gezielter Fallback: Suche nach Emails VON bekannten Lead-Adressen
        if !leadEmails.isEmpty {
            print("[Gmail] Zusaetzliche Suche nach Lead-Emails...")
            for email in leadEmails {
                let emailLower = email.lowercased().trimmingCharacters(in: .whitespaces)
                guard !emailLower.isEmpty else { continue }
                let query = "from:\(emailLower) newer_than:90d"
                let msgs = try await searchGmail(query: query, token: token, maxResults: 5)
                for msg in msgs {
                    guard !seenIds.contains(msg.id) else { continue }
                    seenIds.insert(msg.id)
                    let fromLower = msg.from.lowercased()
                    if fromLower.contains("mf@harpocrates-corp.com") { continue }
                    allReplies.append(msg)
                    print("[Gmail] Email-Match Antwort von: \(msg.from)")
                }
            }
        }

        print("[Gmail] Total: \(allReplies.count) Antworten")
        return allReplies
    }

    // MARK: - Gmail Suche (wiederverwendbar)
    private func searchGmail(query: String, token: String, maxResults: Int = 10) async throws -> [GmailMessage] {
        var components = URLComponents(string: "\(baseURL)/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]

        guard let url = components.url else {
            print("[Gmail] Ungueltige URL fuer Query: \(query)")
            return []
        }

        print("[Gmail] Suche mit Query: \(query)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let freshToken = try await authService.getAccessToken()
            var retryRequest = URLRequest(url: url)
            retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await URLSession.shared.data(for: retryRequest)
            if let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode == 200 {
                return try await parseMessageList(data: retryData, token: freshToken)
            }
            return []
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            print("[Gmail] Suche fehlgeschlagen: \(errBody.prefix(200))")
            return []
        }

        return try await parseMessageList(data: data, token: token)
    }

    private func parseMessageList(data: Data, token: String) async throws -> [GmailMessage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return []
        }
        var results: [GmailMessage] = []
        for msg in messages {
            guard let msgId = msg["id"] as? String else { continue }
            if let detail = try? await fetchMessage(id: msgId, token: token) {
                results.append(detail)
            }
        }
        return results
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

    // MARK: - MIME Email mit professioneller Visitenkarte + Logo + List-Unsubscribe Headers
    private func buildMimeEmail(to: String, from: String, subject: String, body: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let boundary = "HarpoMIME_\(UUID().uuidString)"

        // Add unsubscribe footer to the plain-text body
        let unsubscribeURL = "mailto:unsubscribe@harpocrates-corp.com?subject=Unsubscribe&body=Please%20remove%20\(to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? to)"
        let bodyWithOptOut = body + "\n\n---\nTo unsubscribe from future emails, reply with 'Unsubscribe' or click: \(unsubscribeURL)"

        // Body-Text in HTML-Paragraphen
        let htmlParagraphs = body
            .components(separatedBy: "\n\n")
            .map { p in
                let lines = p.components(separatedBy: "\n").joined(separator: "<br>")
                return "<p style=\"margin:0 0 14px 0;line-height:1.7;color:#2d3748;font-size:14px;font-family:Arial,Helvetica,sans-serif;\">\(lines)</p>"
            }
            .joined(separator: "\n")

        let logoURL = "https://new.harpocrates-corp.com/harpocrates-logo.png"

        // Professionelle HTML-Visitenkarte mit Logo
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
        <body style="margin:0;padding:0;background-color:#f7f7f7;">
        <div style="max-width:600px;margin:0 auto;padding:24px;background-color:#ffffff;">
        \(htmlParagraphs)
        <table cellpadding="0" cellspacing="0" border="0" style="margin-top:32px;border-top:3px solid #1a365d;padding-top:20px;width:100%;">
        <tr>
        <td style="vertical-align:top;padding-right:18px;width:60px;">
        <img src="\(logoURL)" alt="Harpocrates" width="52" height="52" style="display:block;border:0;border-radius:6px;">
        </td>
        <td style="vertical-align:top;font-family:Arial,Helvetica,sans-serif;">
        <p style="margin:0 0 2px 0;font-size:16px;font-weight:bold;color:#1a365d;letter-spacing:0.3px;">Martin F\u{00F6}rster</p>
        <p style="margin:0 0 10px 0;font-size:12px;color:#4a5568;text-transform:uppercase;letter-spacing:0.8px;">CEO & Founder</p>
        <p style="margin:0 0 3px 0;font-size:13px;font-weight:600;color:#2d3748;">Harpocrates Solutions GmbH</p>
        <table cellpadding="0" cellspacing="0" border="0" style="margin-top:6px;">
        <tr><td style="padding:2px 8px 2px 0;font-size:12px;color:#718096;font-family:Arial,Helvetica,sans-serif;">Tel</td><td style="padding:2px 0;font-size:12px;color:#2d3748;font-family:Arial,Helvetica,sans-serif;">+49 172 6348377</td></tr>
        <tr><td style="padding:2px 8px 2px 0;font-size:12px;color:#718096;font-family:Arial,Helvetica,sans-serif;">Mail</td><td style="padding:2px 0;font-size:12px;font-family:Arial,Helvetica,sans-serif;"><a href="mailto:mf@harpocrates-corp.com" style="color:#2b6cb0;text-decoration:none;">mf@harpocrates-corp.com</a></td></tr>
        <tr><td style="padding:2px 8px 2px 0;font-size:12px;color:#718096;font-family:Arial,Helvetica,sans-serif;">Web</td><td style="padding:2px 0;font-size:12px;font-family:Arial,Helvetica,sans-serif;"><a href="https://www.harpocrates-corp.com" style="color:#2b6cb0;text-decoration:none;">www.harpocrates-corp.com</a></td></tr>
        </table>
        <p style="margin:6px 0 0 0;font-size:11px;color:#a0aec0;font-family:Arial,Helvetica,sans-serif;">Berlin, Germany</p>
        </td></tr>
        </table>
        </div>
        <div style="max-width:600px;margin:0 auto;padding:12px 24px;">
        <p style="margin:0;font-size:10px;color:#a0aec0;font-family:Arial,Helvetica,sans-serif;">
        <a href="mailto:unsubscribe@harpocrates-corp.com?subject=Unsubscribe&body=Please%20remove%20\(to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? to)"
           style="color:#a0aec0;text-decoration:underline;">Abmelden / Unsubscribe</a>
        </p>
        </div>
        </body>
        </html>
        """

        let plainB64 = Data(bodyWithOptOut.utf8).base64EncodedString()
        let htmlB64 = Data(html.utf8).base64EncodedString()

        var mime = "From: Martin Foerster <\(from)>\r\n"
        mime += "To: \(to)\r\n"
        mime += "Subject: \(encodedSubject)\r\n"
        mime += "List-Unsubscribe: <mailto:unsubscribe@harpocrates-corp.com?subject=Unsubscribe>\r\n"
        mime += "List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n"
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

    // MARK: - Bounce Detection
    func checkForBounces(sentEmails: [(to: String, subject: String)]) async throws -> [(email: String, bounceType: String)] {
        let token = try await authService.getAccessToken()
        var bounces: [(email: String, bounceType: String)] = []
        var seenIds = Set<String>()

        // Common bounce indicator queries
        let bounceQueries = [
            "subject:\"Delivery Status Notification\" newer_than:30d",
            "subject:\"Undeliverable\" newer_than:30d",
            "subject:\"Mail Delivery Failed\" newer_than:30d",
            "subject:\"Mail delivery failed\" newer_than:30d",
            "subject:\"Delivery Failure\" newer_than:30d",
            "subject:\"Returned mail\" newer_than:30d",
            "from:mailer-daemon newer_than:30d",
            "from:postmaster newer_than:30d"
        ]

        print("[Gmail] Checking for bounce-back messages...")

        for query in bounceQueries {
            let msgs = try await searchGmail(query: query, token: token, maxResults: 20)
            for msg in msgs {
                guard !seenIds.contains(msg.id) else { continue }
                seenIds.insert(msg.id)

                // Determine bounce type from subject and body
                let subjectLower = msg.subject.lowercased()
                let bodyLower = (msg.body + msg.snippet).lowercased()
                let combined = subjectLower + " " + bodyLower

                var bounceType = "unknown"
                if combined.contains("user unknown") || combined.contains("no such user") || combined.contains("does not exist") || combined.contains("550") {
                    bounceType = "hard_bounce_user_unknown"
                } else if combined.contains("mailbox full") || combined.contains("quota exceeded") || combined.contains("over quota") {
                    bounceType = "soft_bounce_mailbox_full"
                } else if combined.contains("connection refused") || combined.contains("host not found") || combined.contains("domain not found") {
                    bounceType = "hard_bounce_domain_error"
                } else if combined.contains("spam") || combined.contains("rejected") || combined.contains("blocked") {
                    bounceType = "soft_bounce_rejected"
                } else if combined.contains("delivery status") || combined.contains("undeliverable") || combined.contains("failed") {
                    bounceType = "hard_bounce_undeliverable"
                }

                // Try to extract the original recipient address from the bounce body
                var matchedEmail = ""
                for sent in sentEmails {
                    if combined.contains(sent.to.lowercased()) {
                        matchedEmail = sent.to
                        break
                    }
                }

                // If we found a bounce but couldn't match a sent address, record with raw snippet
                if matchedEmail.isEmpty {
                    // Try to extract email from body using a simple pattern
                    let emailPattern = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"
                    if let regex = try? NSRegularExpression(pattern: emailPattern),
                       let match = regex.firstMatch(in: msg.body, range: NSRange(msg.body.startIndex..., in: msg.body)),
                       let range = Range(match.range, in: msg.body) {
                        let extracted = String(msg.body[range]).lowercased()
                        // Only count if it's not a harpocrates address
                        if !extracted.contains("harpocrates-corp.com") {
                            matchedEmail = extracted
                        }
                    }
                }

                if !matchedEmail.isEmpty {
                    // Avoid duplicates for same email
                    if !bounces.contains(where: { $0.email.lowercased() == matchedEmail.lowercased() }) {
                        bounces.append((email: matchedEmail, bounceType: bounceType))
                        print("[Gmail] Bounce detected: \(matchedEmail) - \(bounceType)")
                    }
                }
            }
        }

        print("[Gmail] Total bounces found: \(bounces.count)")
        return bounces
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
