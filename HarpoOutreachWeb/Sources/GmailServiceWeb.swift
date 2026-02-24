import Vapor
import Foundation

actor GmailServiceWeb {
  private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
  private let authService: GoogleAuthServiceWeb
  private let client: Client

  init(authService: GoogleAuthServiceWeb, client: Client) {
    self.authService = authService
    self.client = client
  }

  // MARK: - Email senden
  func sendEmail(to: String, from: String, subject: String, body: String) async throws -> String {
    let token = try await authService.getAccessToken(client: client)
    let rawEmail = buildMimeEmail(to: to, from: from, subject: subject, body: body)
    let base64Email = Data(rawEmail.utf8)
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
      let freshToken = try await authService.getAccessToken(client: client)
      let retryResult = try await executeGmailSend(jsonData: jsonData, token: freshToken)
      switch retryResult {
      case .success(let data): return parseMessageId(from: data)
      case .needsRetry: throw GmailError.authExpired
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
    let uri = URI(string: "\(baseURL)/messages/send")
    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(token)")
    headers.add(name: .contentType, value: "application/json")
    let body = ByteBuffer(data: jsonData)
    let response = try await client.post(uri, headers: headers) { req in
      req.body = .init(buffer: body)
    }
    switch response.status.code {
    case 200:
      guard let bytes = response.body else { return .failure(.sendFailed("Empty response")) }
      return .success(Data(buffer: bytes))
    case 401:
      return .needsRetry
    case 403:
      return .failure(.sendFailed("Keine Berechtigung. Pruefe Gmail API Scopes."))
    case 429:
      return .failure(.sendFailed("Rate Limit erreicht."))
    default:
      let errBody = response.body.flatMap { String(buffer: $0) } ?? ""
      return .failure(.sendFailed("HTTP \(response.status.code): \(String(errBody.prefix(200)))"))
    }
  }

  private func parseMessageId(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let messageId = json["id"] as? String {
      return messageId
    }
    return "sent"
  }

  // MARK: - Antworten pruefen
  func checkReplies(sentSubjects: [String], leadEmails: [String] = []) async throws -> [GmailMessage] {
    let token = try await authService.getAccessToken(client: client)
    var allReplies: [GmailMessage] = []
    var seenIds = Set<String>()
    for subject in sentSubjects {
      let cleanSubject = subject
        .replacingOccurrences(of: "Re: ", with: "")
        .replacingOccurrences(of: "RE: ", with: "")
        .replacingOccurrences(of: "Aw: ", with: "")
        .replacingOccurrences(of: "AW: ", with: "")
        .trimmingCharacters(in: .whitespaces)
      guard !cleanSubject.isEmpty else { continue }
      let query = "in:inbox subject:\"\(cleanSubject)\" -from:me newer_than:90d"
      let msgs = try await searchGmail(query: query, token: token, maxResults: 10)
      for msg in msgs {
        guard !seenIds.contains(msg.id) else { continue }
        seenIds.insert(msg.id)
        if msg.from.lowercased().contains("mf@harpocrates-corp.com") { continue }
        allReplies.append(msg)
      }
    }
    if allReplies.isEmpty && !leadEmails.isEmpty {
      for email in leadEmails {
        let emailLower = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard !emailLower.isEmpty else { continue }
        let query = "in:inbox from:\(emailLower) newer_than:90d"
        let msgs = try await searchGmail(query: query, token: token, maxResults: 5)
        for msg in msgs {
          guard !seenIds.contains(msg.id) else { continue }
          seenIds.insert(msg.id)
          if msg.from.lowercased().contains("mf@harpocrates-corp.com") { continue }
          allReplies.append(msg)
        }
      }
    }
    return allReplies
  }

  // MARK: - Gmail Suche
  private func searchGmail(query: String, token: String, maxResults: Int = 10) async throws -> [GmailMessage] {
    var components = URLComponents(string: "\(baseURL)/messages")!
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "maxResults", value: "\(maxResults)")
    ]
    guard let url = components.url else { return [] }
    let uri = URI(string: url.absoluteString)
    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(token)")
    let response = try await client.get(uri, headers: headers)
    guard response.status == .ok, let bytes = response.body else { return [] }
    let data = Data(buffer: bytes)
    return try await parseMessageList(data: data, token: token)
  }

  private func parseMessageList(data: Data, token: String) async throws -> [GmailMessage] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let messages = json["messages"] as? [[String: Any]] else { return [] }
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
    let uri = URI(string: "\(baseURL)/messages/\(id)?format=full")
    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(token)")
    let response = try await client.get(uri, headers: headers)
    guard let bytes = response.body else { throw GmailError.parseFailed }
    let data = Data(buffer: bytes)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GmailError.parseFailed
    }
    let payload = json["payload"] as? [String: Any] ?? [:]
    let hdrs = payload["headers"] as? [[String: String]] ?? []
    var from = "", subject = "", date = ""
    for header in hdrs {
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
          if let decoded = Data(base64Encoded: padded), let text = String(data: decoded, encoding: .utf8) {
            body = text
          }
        }
      }
    }
    return GmailMessage(id: id, from: from, subject: subject, date: date, snippet: snippet, body: body)
  }

  // MARK: - MIME Email aufbauen
  private func buildMimeEmail(to: String, from: String, subject: String, body: String) -> String {
    let encodedSubject = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
    let boundary = "HarpoMIME_\(UUID().uuidString)"
    let logoURL = "https://new.harpocrates-corp.com/harpocrates-logo.png"
    let htmlParagraphs = body
      .components(separatedBy: "\n\n")
      .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
      .joined(separator: "\n")
    let html = """
    <html><body>
    \(htmlParagraphs)
    <br><table><tr><td><img src='\(logoURL)' width='60'/></td>
    <td style='padding-left:10px;font-family:Arial;font-size:12px;color:#333'>
    <strong>Martin F&#246;rster</strong><br>CEO &amp; Founder<br>
    Harpocrates Solutions GmbH<br>
    Tel: +49 172 6348377<br>
    <a href='mailto:mf@harpocrates-corp.com'>mf@harpocrates-corp.com</a><br>
    <a href='https://www.harpocrates-corp.com'>www.harpocrates-corp.com</a><br>
    Berlin, Germany
    </td></tr></table>
    <p style='font-size:10px'><a href='mailto:mf@harpocrates-corp.com?subject=Unsubscribe'>Abmelden / Unsubscribe</a></p>
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
    mime += "Content-Transfer-Encoding: base64\r\n\r\n"
    mime += "\(plainB64)\r\n"
    mime += "--\(boundary)\r\n"
    mime += "Content-Type: text/html; charset=\"UTF-8\"\r\n"
    mime += "Content-Transfer-Encoding: base64\r\n\r\n"
    mime += "\(htmlB64)\r\n"
    mime += "--\(boundary)--"
    return mime
  }

  // MARK: - Types
  struct GmailMessage: Identifiable, Codable, Sendable {
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
