import Foundation

class GoogleSheetsService {
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Sheet initialisieren (Tracking-Header schreiben)
    func initializeSheet(spreadsheetID: String) async throws {
        print("[Sheets] Initialisiere Sheet: \(spreadsheetID.prefix(10))...")
        let headers: [String] = [
            "Datum", "Typ", "Unternehmen", "Ansprechpartner",
            "Email", "Betreff", "Inhalt (Auszug)", "Status", "Zusammenfassung"
        ]
        let existing = try await readRow(spreadsheetID: spreadsheetID, range: "Sheet1!A1:I1")
        if existing.isEmpty {
            try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: headers)
            print("[Sheets] Header geschrieben")
        } else {
            print("[Sheets] Header bereits vorhanden")
        }
    }

    // MARK: - Email-Event loggen (Tracking)
    func logEmailEvent(spreadsheetID: String, lead: Lead, emailType: String,
                       subject: String, body: String, summary: String) async throws {
        print("[Sheets] Logge Email-Event: \(emailType) fuer \(lead.name)")
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
        try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: row)
        print("[Sheets] Email-Event erfolgreich geloggt")
    }

    // MARK: - Antwort loggen
    func logReplyReceived(spreadsheetID: String, lead: Lead,
                          replySubject: String, replySnippet: String,
                          replyFrom: String) async throws {
        print("[Sheets] Logge Antwort von \(lead.name)")
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
        try await appendRow(spreadsheetID: spreadsheetID, sheet: "Sheet1", values: row)
        print("[Sheets] Antwort erfolgreich geloggt")
    }

    // MARK: - Alle Tracking-Daten lesen
    func readAllLeads(spreadsheetID: String) async throws -> [[String]] {
        print("[Sheets] Lese alle Daten...")
        let result = try await readRow(spreadsheetID: spreadsheetID, range: "Sheet1!A:I")
        print("[Sheets] \(result.count) Zeilen gelesen")
        return result
    }

    // MARK: - Low-Level: Zeile anhaengen
    private func appendRow(spreadsheetID: String, sheet: String = "Sheet1",
                           values: [String]) async throws {
        let token = try await authService.getAccessToken()
        let range = "\(sheet)!A:I"
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range

        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange):append?valueInputOption=USER_ENTERED"
        print("[Sheets] appendRow URL: \(urlStr.prefix(80))...")

        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["values": [values]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SheetsError.writeFailed("Keine HTTP Response")
        }

        if http.statusCode == 401 {
            // Token refresh und nochmal versuchen
            print("[Sheets] 401 - Token wird erneuert...")
            let freshToken = try await authService.getAccessToken()
            var retryRequest = URLRequest(url: URL(string: urlStr)!)
            retryRequest.httpMethod = "POST"
            retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (retryData, retryResp) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttp = retryResp as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                let err = String(data: retryData, encoding: .utf8) ?? ""
                print("[Sheets] Retry fehlgeschlagen: \(err.prefix(200))")
                throw SheetsError.writeFailed(err)
            }
            print("[Sheets] appendRow Retry erfolgreich (\(retryHttp.statusCode))")
            return
        }

        guard (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? ""
            print("[Sheets] appendRow FEHLER HTTP \(http.statusCode): \(err.prefix(200))")
            throw SheetsError.writeFailed("HTTP \(http.statusCode): \(err)")
        }
        print("[Sheets] appendRow erfolgreich (\(http.statusCode))")
    }

    // MARK: - Low-Level: Zeilen lesen
    private func readRow(spreadsheetID: String, range: String) async throws -> [[String]] {
        let token = try await authService.getAccessToken()
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range

        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange)"
        print("[Sheets] readRow URL: \(urlStr.prefix(80))...")

        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[Sheets] readRow: Keine HTTP Response")
            return []
        }

        if http.statusCode == 401 {
            print("[Sheets] readRow 401 - Token wird erneuert...")
            let freshToken = try await authService.getAccessToken()
            var retryRequest = URLRequest(url: URL(string: urlStr)!)
            retryRequest.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttp = retryResp as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                print("[Sheets] readRow Retry fehlgeschlagen")
                return []
            }
            guard let json = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any],
                  let values = json["values"] as? [[String]] else {
                return []
            }
            return values
        }

        guard (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? ""
            print("[Sheets] readRow FEHLER HTTP \(http.statusCode): \(err.prefix(200))")
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[String]] else {
            print("[Sheets] readRow: Keine Daten im Response")
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
