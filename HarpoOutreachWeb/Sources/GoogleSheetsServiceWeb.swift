import Vapor
import Foundation

actor GoogleSheetsServiceWeb {
  private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
  private let authService: GoogleAuthServiceWeb
  private let client: Client

  init(authService: GoogleAuthServiceWeb, client: Client) {
    self.authService = authService
    self.client = client
  }

  // MARK: - Spreadsheet-ID bereinigen
  private func cleanSpreadsheetID(_ rawID: String) -> String {
    var id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
    if id.contains("spreadsheets/d/") {
      if let range = id.range(of: "spreadsheets/d/") {
        let start = range.upperBound
        let rest = String(id[start...])
        if let slashIdx = rest.firstIndex(of: "/") {
          id = String(rest[..<slashIdx])
        } else {
          id = rest
        }
      }
    }
    id = id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return id
  }

  // MARK: - URL sicher bauen
  private func buildURL(spreadsheetID: String, range: String, action: String = "") -> URL? {
    let cleanID = cleanSpreadsheetID(spreadsheetID)
    var path = "/v4/spreadsheets/\(cleanID)/values/\(range)"
    if !action.isEmpty {
      path += ":\(action)"
    }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "sheets.googleapis.com"
    components.path = path
    if action == "append" {
      components.queryItems = [
        URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")
      ]
    }
    return components.url
  }

  // MARK: - Sheet initialisieren
  func initializeSheet(spreadsheetID: String) async throws {
    let headers: [String] = [
      "Datum", "Typ", "Unternehmen", "Ansprechpartner",
      "Email", "Betreff", "Inhalt (Auszug)", "Status", "Zusammenfassung"
    ]
    let existing = try await readRow(spreadsheetID: spreadsheetID, range: "Sheet1!A1:I1")
    if existing.isEmpty {
      try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: headers)
    }
  }

  // MARK: - Email-Event loggen
  func logEmailEvent(spreadsheetID: String, lead: Lead, emailType: String,
                     subject: String, body: String, summary: String) async throws {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
    let bodyExcerpt = String(body.prefix(300)).replacingOccurrences(of: "\n", with: " ")
    let row: [String] = [
      dateFormatter.string(from: Date()),
      emailType,
      lead.company,
      lead.name,
      lead.email,
      subject,
      bodyExcerpt,
      lead.status.rawValue,
      summary
    ]
    try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: row)
  }

  // MARK: - Antwort loggen
  func logReplyReceived(spreadsheetID: String, lead: Lead,
                        replySubject: String, replySnippet: String, replyFrom: String) async throws {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
    let row: [String] = [
      dateFormatter.string(from: Date()),
      "Antwort erhalten",
      lead.company,
      lead.name,
      replyFrom,
      replySubject,
      String(replySnippet.prefix(300)).replacingOccurrences(of: "\n", with: " "),
      lead.status.rawValue,
      "Antwort von \(lead.name) (\(lead.company)) erhalten auf Outreach-Email"
    ]
    try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: row)
  }

  // MARK: - Alle Daten lesen
  func readAllLeads(spreadsheetID: String) async throws -> [[String]] {
    return try await readRow(spreadsheetID: spreadsheetID, range: "Sheet1!A:I")
  }

  // MARK: - Low-Level: Zeile anhaengen
  private func appendRow(spreadsheetID: String, sheet: String = "Sheet1", values: [String]) async throws {
    let token = try await authService.getAccessToken(client: client)
    let range = "\(sheet)!A:I"
    guard let url = buildURL(spreadsheetID: spreadsheetID, range: range, action: "append") else {
      throw SheetsError.writeFailed("Ungueltige URL fuer Spreadsheet-ID: \(spreadsheetID.prefix(20))")
    }
    let uri = URI(string: url.absoluteString)
    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(token)")
    headers.add(name: .contentType, value: "application/json")
    let bodyObj: [String: Any] = ["values": [values]]
    let jsonData = try JSONSerialization.data(withJSONObject: bodyObj)
    let buffer = ByteBuffer(data: jsonData)
    let response = try await client.post(uri, headers: headers) { req in
      req.body = .init(buffer: buffer)
    }
    if response.status.code == 401 {
      let freshToken = try await authService.getAccessToken(client: client)
      var retryHeaders = HTTPHeaders()
      retryHeaders.add(name: .authorization, value: "Bearer \(freshToken)")
      retryHeaders.add(name: .contentType, value: "application/json")
      let retryResponse = try await client.post(uri, headers: retryHeaders) { req in
        req.body = .init(buffer: buffer)
      }
      guard (200...299).contains(Int(retryResponse.status.code)) else {
        let err = retryResponse.body.flatMap { String(buffer: $0) } ?? ""
        throw SheetsError.writeFailed(err)
      }
      return
    }
    guard (200...299).contains(Int(response.status.code)) else {
      let err = response.body.flatMap { String(buffer: $0) } ?? ""
      throw SheetsError.writeFailed("HTTP \(response.status.code): \(err)")
    }
  }

  // MARK: - Low-Level: Zeilen lesen
  private func readRow(spreadsheetID: String, range: String) async throws -> [[String]] {
    let token = try await authService.getAccessToken(client: client)
    guard let url = buildURL(spreadsheetID: spreadsheetID, range: range) else { return [] }
    let uri = URI(string: url.absoluteString)
    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(token)")
    let response = try await client.get(uri, headers: headers)
    if response.status.code == 401 {
      let freshToken = try await authService.getAccessToken(client: client)
      var retryHeaders = HTTPHeaders()
      retryHeaders.add(name: .authorization, value: "Bearer \(freshToken)")
      let retryResponse = try await client.get(uri, headers: retryHeaders)
      guard let bytes = retryResponse.body else { return [] }
      return parseValuesResponse(data: Data(buffer: bytes))
    }
    guard (200...299).contains(Int(response.status.code)), let bytes = response.body else { return [] }
    return parseValuesResponse(data: Data(buffer: bytes))
  }

  private func parseValuesResponse(data: Data) -> [[String]] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let values = json["values"] as? [[String]] else { return [] }
    return values
  }

  // MARK: - Errors
  enum SheetsError: LocalizedError {
    case writeFailed(String)
    var errorDescription: String? {
      switch self {
      case .writeFailed(let msg): return "Google Sheets Fehler: \(String(msg.prefix(200)))"
      }
    }
  }
}
