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

    // MARK: - Newsletter HTML Email senden
    func sendEmail(to: String, subject: String, htmlBody: String, accessToken: String, from: String) async throws {
        let token = try await authService.getAccessToken()
        print("[Gmail] Sende Newsletter an \(to) von \(from)")
        let rawEmail = buildHtmlMimeEmail(to: to, from: from, subject: subject, htmlBody: htmlBody)

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
        case .success(_):
            print("[Gmail] Newsletter gesendet an \(to)")
        case .needsRetry:
            let freshToken = try await authService.getAccessToken()
            let retryResult = try await executeGmailSend(jsonData: jsonData, token: freshToken)
            switch retryResult {
            case .success(_):
                print("[Gmail] Newsletter Retry erfolgreich an \(to)")
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
            let query = "in:inbox subject:\(quotedSubject) -from:me newer_than:90d"
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
        if allReplies.isEmpty && !leadEmails.isEmpty {
            print("[Gmail] Kein Subject-Match - suche nach Lead-Emails...")
            for email in leadEmails {
                let emailLower = email.lowercased().trimmingCharacters(in: .whitespaces)
                guard !emailLower.isEmpty else { continue }
                let query = "in:inbox from:\(emailLower) newer_than:90d"
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

    // MARK: - MIME Email mit professioneller Visitenkarte + Logo
    private func buildMimeEmail(to: String, from: String, subject: String, body: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let boundary = "HarpoMIME_\(UUID().uuidString)"

        let htmlParagraphs = body
            .components(separatedBy: "\n\n")
            .map { p in
                let lines = p.components(separatedBy: "\n").joined(separator: "<br>")
                return "<p style=\"margin:0 0 12px 0;line-height:1.6;color:#333333;\">\(lines)</p>"
            }
            .joined(separator: "\n")

        let logoURL = "https://new.harpocrates-corp.com/harpocrates-logo.png"

        let html = """
        <!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head>
        <body style=\"font-family:'Helvetica Neue',Arial,sans-serif;font-size:14px;color:#333;margin:0;padding:20px;\">
        \(htmlParagraphs)
        <table cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"margin-top:24px;border-top:2px solid #1a1a2e;padding-top:16px;\">
        <tr><td style=\"padding-right:16px;vertical-align:top;\"><img src=\"\(logoURL)\" alt=\"Harpocrates\" width=\"80\" style=\"border-radius:8px;\"></td>
        <td style=\"vertical-align:top;font-family:'Helvetica Neue',Arial,sans-serif;\">
        <strong style=\"font-size:14px;color:#1a1a2e;\">Martin F\u{00F6}rster</strong><br>
        <span style=\"font-size:12px;color:#666;\">CEO & Founder</span><br>
        <span style=\"font-size:12px;color:#666;\">Harpocrates Solutions GmbH</span><br>
        <span style=\"font-size:11px;color:#999;\">---</span><br>
        <span style=\"font-size:12px;color:#666;\">Tel&nbsp; +49 172 6348377</span><br>
        <span style=\"font-size:12px;color:#666;\">Mail&nbsp; <a href=\"mailto:mf@harpocrates-corp.com\" style=\"color:#0f3460;\">mf@harpocrates-corp.com</a></span><br>
        <span style=\"font-size:12px;color:#666;\">Web&nbsp; <a href=\"https://www.harpocrates-corp.com\" style=\"color:#0f3460;\">www.harpocrates-corp.com</a></span><br>
        <span style=\"font-size:11px;color:#999;\">Berlin, Germany</span>
        </td></tr></table>
        <p style=\"margin-top:20px;font-size:10px;color:#999;\">
        <a href=\"mailto:mf@harpocrates-corp.com?subject=Unsubscribe&body=Bitte%20entfernen%20Sie%20mich%20von%20Ihrer%20Mailingliste.\" style=\"color:#999;\">Abmelden / Unsubscribe</a></p>
        </body></html>
        """

        let plainB64 = Data(body.utf8).base64EncodedString()
        let htmlB64 = Data(html.utf8).base64EncodedString()

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

    // MARK: - Newsletter HTML MIME Builder
    private func buildHtmlMimeEmail(to: String, from: String, subject: String, htmlBody: String) -> String {
        let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let boundary = "HarpoNewsletter_\(UUID().uuidString)"

        // Strip HTML tags for plain text version
        let plainText = htmlBody
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let plainB64 = Data(plainText.utf8).base64EncodedString()
        let htmlB64 = Data(htmlBody.utf8).base64EncodedString()

        var mime = "From: Harpocrates Corp <\(from)>\r\n"
        mime += "To: \(to)\r\n"
        mime += "Subject: \(encodedSubject)\r\n"
        mime += "MIME-Version: 1.0\r\n"
        mime += "Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n"
        mime += "List-Unsubscribe: <mailto:mf@harpocrates-corp.com?subject=Unsubscribe>\r\n"
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
