import Foundation

class GoogleSheetsService {
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let authService: GoogleAuthService
    
    init(authService: GoogleAuthService) {
        self.authService = authService
    }
    
    // MARK: - Sheet initialisieren (Header schreiben)
    func initializeSheet(spreadsheetID: String) async throws {
        let headers: [String] = [
            "Unternehmen", "Industrie", "Region", "Website",
            "Ansprechpartner", "Titel", "Email", "Email verifiziert",
            "LinkedIn", "Status", "Email Betreff", "Email gesendet am",
            "Follow-Up gesendet am", "Antwort erhalten", "Notizen"
        ]
        
        let existing = try await readRow(spreadsheetID: spreadsheetID,
                                         range: "Sheet1!A1:O1")
        if existing.isEmpty {
            try await appendRow(spreadsheetID: spreadsheetID, values: headers)
        }
    }
    
    // MARK: - Lead in Sheet schreiben
    func logLead(spreadsheetID: String, lead: Lead) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        let row: [String] = [
            lead.company,  // company is now a String (company name)
            "",  // industry not available in Lead
            "",  // region not available in Lead
            "",  // website not available in Lead
            lead.name,
            lead.title,
            lead.email,
            lead.emailVerified ? "Ja" : "Nein",
            lead.linkedInURL,
            lead.status.rawValue,
            lead.draftedEmail?.subject ?? "",
            lead.dateEmailSent.map { dateFormatter.string(from: $0) } ?? "",
            lead.dateFollowUpSent.map { dateFormatter.string(from: $0) } ?? "",
            lead.replyReceived.isEmpty ? "Nein" : "Ja",
            lead.verificationNotes
        ]
        
        try await appendRow(spreadsheetID: spreadsheetID, values: row)
    }
    
    // MARK: - Lead-Zeile aktualisieren
    func updateLead(spreadsheetID: String, lead: Lead) async throws {
        // Zeile finden anhand Email
        let allData = try await readRow(spreadsheetID: spreadsheetID,
                                        range: "Sheet1!A:O")
        var rowIndex = -1
        for (i, row) in allData.enumerated() {
            if row.count > 6 && row[6] == lead.email && row[4] == lead.name {
                rowIndex = i + 1 // Sheets ist 1-basiert
                break
            }
        }
        
        guard rowIndex > 0 else {
            // Nicht gefunden, neu anlegen
            try await logLead(spreadsheetID: spreadsheetID, lead: lead)
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        let row: [String] = [
            lead.company,  // company is now a String (company name)
            "",  // industry not available in Lead
            "",  // region not available in Lead
            "",  // website not available in Lead
            lead.name,
            lead.title,
            lead.email,
            lead.emailVerified ? "Ja" : "Nein",
            lead.linkedInURL,
            lead.status.rawValue,
            lead.draftedEmail?.subject ?? "",
            lead.dateEmailSent.map { dateFormatter.string(from: $0) } ?? "",
            lead.dateFollowUpSent.map { dateFormatter.string(from: $0) } ?? "",
            lead.replyReceived.isEmpty ? "Nein" : "Ja",
            lead.verificationNotes
        ]
        
        let range = "Sheet1!A\(rowIndex):O\(rowIndex)"
        try await writeRow(spreadsheetID: spreadsheetID, range: range, values: row)
    }
    
    // MARK: - Alle Daten lesen
    func readAllLeads(spreadsheetID: String) async throws -> [[String]] {
        return try await readRow(spreadsheetID: spreadsheetID, range: "Sheet1!A:O")
    }
    
    // MARK: - Low-Level: Zeile anhaengen
    private func appendRow(spreadsheetID: String, values: [String]) async throws {
        let token = try await authService.getAccessToken()
        let range = "Sheet1!A:O"
        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(range):append?valueInputOption=USER_ENTERED"
        
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["values": [values]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? ""
            throw SheetsError.writeFailed(err)
        }
    }
    
    // MARK: - Low-Level: Zeile schreiben (ueberschreiben)
    private func writeRow(spreadsheetID: String, range: String, values: [String]) async throws {
        let token = try await authService.getAccessToken()
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range
        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange)?valueInputOption=USER_ENTERED"
        
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["values": [values]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? ""
            throw SheetsError.writeFailed(err)
        }
    }
    
    // MARK: - Low-Level: Zeilen lesen
    private func readRow(spreadsheetID: String, range: String) async throws -> [[String]] {
        let token = try await authService.getAccessToken()
        let encodedRange = range.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? range
        let urlStr = "\(baseURL)/\(spreadsheetID)/values/\(encodedRange)"
        
        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
