import Foundation

class GoogleSheetsService {
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Sheet initialisieren (Tracking-Header schreiben)
    func initializeSheet(spreadsheetID: String) async throws {
        let headers: [String] = [
            "Datum", "Typ", "Unternehmen", "Ansprechpartner",
            "Email", "Betreff", "Inhalt (Auszug)",
            "Status", "Zusammenfassung"
        ]

        let existing = try await readRow(spreadsheetID: spreadsheetID,
                                         range: "Sheet1!A1:I1")
        if existing.isEmpty {
            try await appendRow(spreadsheetID: spreadsheetID,
                               sheet: "Sheet1", values: headers)
        }
    }

    // MARK: - Email-Event loggen (Tracking)
    func logEmailEvent(spreadsheetID: String, lead: Lead,
                       emailType: String, subject: String,
                       body: String, summary: String) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        let bodyExcerpt = String(body.prefix(300))
            .replacingOccurrences(of: "\n", with: " ")

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

        try await appendRow(spreadsheetID: spreadsheetID,
                           sheet: "Sheet1", values: row)
    }

    // MARK: - Antwort loggen
    func logReplyReceived(spreadsheetID: String, lead: Lead,
                          replySubject: String, replySnippet: String,
                          replyFrom: String) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        let row: [String] = [
            dateFormatter.string(from: Date()),
            "Antwort erhalten",
            lead.company,
            lead.name,
            replyFrom,
            replySubject,
            String(replySnippet.prefix(300))
                .replacingOccurrences(of: "\n", with: " "),
            lead.status.rawValue,
            "Antwort von \(lead.name) (\(lead.company)) erhalten auf Outreach-Email"
        ]

        try await appendRow(spreadsheetID: spreadsheetID,
                           sheet: "Sheet1", values: row)
    }

    // MARK: - Alle Tracking-Daten lesen
    func readAllLeads(spreadsheetID: String) async throws -> [[String]] {
        return try await readRow(spreadsheetID: spreadsheetID,
                                range: "Sheet1!A:I")
    }

    // MARK: - Low-Level: Zeile anhaengen
    private func appendRow(spreadsheetID: String,
                          sheet: String = "Sheet1",
                          values: [String]) async throws {
        let token = try await authService.getAccessToken()
        let range = "\(sheet)!A:I"
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range
        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange):append?valueInputOption=USER_ENTERED"

        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",
                        forHTTPHeaderField: "Authorization")
        request.setValue("application/json",
                        forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["values": [values]]
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(
            for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? ""
            throw SheetsError.writeFailed(err)
        }
    }

    // MARK: - Low-Level: Zeilen lesen
    private func readRow(spreadsheetID: String,
                        range: String) async throws -> [[String]] {
        let token = try await authService.getAccessToken()
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range
        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange)"

        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue("Bearer \(token)",
                        forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(
            for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(
            with: data) as? [String: Any],
              let values = json["values"] as? [[String]] else {
            return []
        }
        return values
    }

    // MARK: - Errors
    enum SheetsError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let msg):
                return "Google Sheets Fehler: \(String(msg.prefix(200)))"
            }
        }
    }
}
