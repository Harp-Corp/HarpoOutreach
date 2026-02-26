import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSVImportService
// Verbesserung 9: Kontakt-Import aus CSV/LinkedIn Export
class CSVImportService {
    
    // MARK: - Import Result
    struct ImportResult {
        var imported: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
        var leads: [Lead] = []
    }
    
    // MARK: - Column Mapping
    struct ColumnMapping {
        var nameColumn: Int = 0
        var emailColumn: Int = 3
        var companyColumn: Int = 2
        var titleColumn: Int = 1
        var phoneColumn: Int = -1
        var linkedInColumn: Int = -1
        
        // LinkedIn export default mapping
        static let linkedin = ColumnMapping(
            nameColumn: 0, emailColumn: 3, companyColumn: 2,
            titleColumn: 1, phoneColumn: -1, linkedInColumn: 4
        )
        
        // Generic CSV mapping
        static let generic = ColumnMapping(
            nameColumn: 0, emailColumn: 1, companyColumn: 2,
            titleColumn: 3, phoneColumn: 4, linkedInColumn: 5
        )
    }
    
    // MARK: - Parse CSV
    func parseCSV(content: String, hasHeader: Bool = true, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in content {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == delimiter && !insideQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if char == "\n" && !insideQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        // Last row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        
        if hasHeader && !rows.isEmpty {
            rows.removeFirst()
        }
        return rows
    }
    
    // MARK: - Auto-detect Columns
    func autoDetectMapping(headers: [String]) -> ColumnMapping {
        var mapping = ColumnMapping()
        let lower = headers.map { $0.lowercased() }
        
        for (i, h) in lower.enumerated() {
            if h.contains("name") || h.contains("first") || h == "full name" {
                mapping.nameColumn = i
            }
            if h.contains("email") || h.contains("e-mail") || h.contains("mail") {
                mapping.emailColumn = i
            }
            if h.contains("company") || h.contains("organization") || h.contains("firma") || h.contains("unternehmen") {
                mapping.companyColumn = i
            }
            if h.contains("title") || h.contains("position") || h.contains("rolle") || h.contains("job") {
                mapping.titleColumn = i
            }
            if h.contains("phone") || h.contains("telefon") || h.contains("tel") {
                mapping.phoneColumn = i
            }
            if h.contains("linkedin") || h.contains("profile") || h.contains("url") {
                mapping.linkedInColumn = i
            }
        }
        return mapping
    }
    
    // MARK: - Import Leads from CSV
    func importLeads(
        content: String,
        mapping: ColumnMapping? = nil,
        existingLeads: [Lead],
        hasHeader: Bool = true,
        delimiter: Character = ","
    ) -> ImportResult {
        var result = ImportResult()
        let rows = parseCSV(content: content, hasHeader: false, delimiter: delimiter)
        
        guard !rows.isEmpty else {
            result.errors.append("CSV file is empty")
            return result
        }
        
        // Auto-detect mapping from headers if not provided
        let effectiveMapping: ColumnMapping
        if let mapping = mapping {
            effectiveMapping = mapping
        } else if hasHeader, let headers = rows.first {
            effectiveMapping = autoDetectMapping(headers: headers)
        } else {
            effectiveMapping = .generic
        }
        
        let dataRows = hasHeader ? Array(rows.dropFirst()) : rows
        let existingSet = Set(existingLeads.map {
            "\($0.name.lowercased())|\($0.company.lowercased())"
        })
        
        for (rowIndex, row) in dataRows.enumerated() {
            // Extract fields safely
            let name = safeGet(row, effectiveMapping.nameColumn)
            let email = safeGet(row, effectiveMapping.emailColumn)
            let company = safeGet(row, effectiveMapping.companyColumn)
            let title = safeGet(row, effectiveMapping.titleColumn)
            let phone = safeGet(row, effectiveMapping.phoneColumn)
            let linkedIn = safeGet(row, effectiveMapping.linkedInColumn)
            
            // Validate required fields
            guard !name.isEmpty else {
                result.errors.append("Row \(rowIndex + 1): Missing name")
                result.skipped += 1
                continue
            }
            guard !company.isEmpty else {
                result.errors.append("Row \(rowIndex + 1): Missing company for \(name)")
                result.skipped += 1
                continue
            }
            
            // Check for duplicates
            let key = "\(name.lowercased())|\(company.lowercased())"
            if existingSet.contains(key) {
                result.skipped += 1
                continue
            }
            
            let lead = Lead(
                name: name,
                title: title,
                company: company,
                email: email,
                emailVerified: false,
                linkedInURL: linkedIn,
                phone: phone,
                status: .identified,
                source: "CSV Import",
                isManuallyCreated: true
            )
            result.leads.append(lead)
            result.imported += 1
        }
        
        return result
    }
    
    // MARK: - Export Leads to CSV
    func exportLeads(_ leads: [Lead]) -> String {
        var csv = "Name,Title,Company,Email,Verified,Status,LinkedIn,Phone,Source\n"
        for lead in leads {
            let row = [
                escapeCSV(lead.name),
                escapeCSV(lead.title),
                escapeCSV(lead.company),
                escapeCSV(lead.email),
                lead.emailVerified ? "Yes" : "No",
                lead.status.rawValue,
                escapeCSV(lead.linkedInURL),
                escapeCSV(lead.phone),
                escapeCSV(lead.source)
            ].joined(separator: ",")
            csv += row + "\n"
        }
        return csv
    }
    
    // MARK: - Helpers
    private func safeGet(_ row: [String], _ index: Int) -> String {
        guard index >= 0 && index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
