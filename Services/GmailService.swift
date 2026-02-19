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
            // URLComponents fuer sichere Query-Konstruktion
            let query = "in:inbox subject:\(cleanSubject) -from:me newer_than:90d"
            var components = URLComponents(string: "\(baseURL)/messages")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "10")
            ]
            guard let url = components.url else {
                print("[Gmail] Ungueltige URL fuer Subject: \(cleanSubject)")
                continue
            }
            print("[Gmail] Suche Antworten: \(cleanSubject)")
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                print("[Gmail] checkReplies HTTP \(http.statusCode): \(errBody.prefix(300))")
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else {
                print("[Gmail] Keine Antworten fuer: \(cleanSubject)")
                continue
            }
            print("[Gmail] \(messages.count) Nachrichten gefunden")
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
                   let bd = part["body"] as? [String: Any], let b64 = bd["data"] as? String {
                    let padded = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: padded), let text = String(data: decoded, encoding: .utf8) {
                        body = text
                    }
                }
            }
        } else if let bd = payload["body"] as? [String: Any], let b64 = bd["data"] as? String {
            let padded = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let decoded = Data(base64Encoded: padded), let text = String(data: decoded, encoding: .utf8) {
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
                return "<p style=\"margin:0 0 12px 0;line-height:1.6;\">\(lines)</p>"
            }
            .joined(separator: "\n")
        // Professionelle HTML-Visitenkarte
        let html = "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head>"
            + "<body style=\"font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1a1a1a;max-width:600px;margin:0 auto;padding:20px;\">"
            + "<div style=\"margin-bottom:30px;\">"
            + htmlParagraphs
            + "</div>"
            + "<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"border-top:2px solid #0066cc;padding-top:16px;margin-top:30px;font-family:Arial,Helvetica,sans-serif;\">"
            + "<tr><td style=\"vertical-align:top;padding-right:16px;\">"
            + "<div style=\"width:3px;height:80px;background:#0066cc;\">&nbsp;</div>"
            + "</td><td style=\"vertical-align:top;\">"
            + "<p style=\"margin:0;font-size:15px;font-weight:bold;color:#1a1a1a;\">Martin F\u{00F6}rster</p>"
            + "<p style=\"margin:2px 0 0 0;font-size:12px;color:#666;\">CEO &amp; Founder</p>"
            + "<p style=\"margin:10px 0 0 0;font-size:13px;font-weight:bold;color:#0066cc;\">Harpocrates Solutions GmbH</p>"
            + "<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"margin-top:8px;font-size:12px;color:#555;\">"
            + "<tr><td style=\"padding:2px 8px 2px 0;color:#999;\">Tel</td><td style=\"padding:2px 0;\">+49 172 6348377</td></tr>"
            + "<tr><td style=\"padding:2px 8px 2px 0;color:#999;\">Email</td><td style=\"padding:2px 0;\"><a href=\"mailto:mf@harpocrates-corp.com\" style=\"color:#0066cc;text-decoration:none;\">mf@harpocrates-corp.com</a></td></tr>"
            + "<tr><td style=\"padding:2px 8px 2px 0;color:#999;\">Web</td><td style=\"padding:2px 0;\"><a href=\"https://www.harpocrates-corp.com\" style=\"color:#0066cc;text-decoration:none;\">www.harpocrates-corp.com</a></td></tr>"
            + "<tr><td style=\"padding:2px 8px 2px 0;color:#999;\">Ort</td><td style=\"padding:2px 0;\">Berlin, Germany</td></tr>"
            + "</table>"
            + "</td></tr></table>"
            + "<p style=\"margin-top:20px;font-size:9px;color:#999;\"><a href=\"mailto:mf@harpocrates-corp.com?subject=Unsubscribe&amp;body=Bitte%20entfernen%20Sie%20mich%20von%20Ihrer%20Mailingliste.\" style=\"color:#999;\">Abmelden / Unsubscribe</a></p>"
            + "</body></html>"
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
