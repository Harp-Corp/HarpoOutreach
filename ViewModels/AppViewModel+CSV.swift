import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - AppViewModel+CSV
// Handles: CSV import/export for leads and companies (task 12)
// Uses NSSavePanel / NSOpenPanel for file dialogs (macOS only)
// Delegates actual CSV serialization to DatabaseService.shared

extension AppViewModel {

    // MARK: - Export Leads CSV
    func exportLeadsCSV() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "harpo_leads_export.csv"
        panel.title = "Export Leads as CSV"
        panel.message = "Choose a location to save the leads export."
        if panel.runModal() == .OK, let url = panel.url {
            let csv = DatabaseService.shared.exportLeadsCSV()
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "\(leads.count) leads exported to \(url.lastPathComponent)"
            } catch {
                errorMessage = "CSV export failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    // MARK: - Export Companies CSV
    func exportCompaniesCSV() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "harpo_companies_export.csv"
        panel.title = "Export Companies as CSV"
        panel.message = "Choose a location to save the companies export."
        if panel.runModal() == .OK, let url = panel.url {
            let csv = DatabaseService.shared.exportCompaniesCSV()
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "\(companies.count) companies exported to \(url.lastPathComponent)"
            } catch {
                errorMessage = "CSV export failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    // MARK: - Import Leads from CSV
    func importLeadsFromCSV() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.title = "Import Leads from CSV"
        panel.message = "Select a CSV file to import leads."
        if panel.runModal() == .OK, let url = panel.url {
            guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
                errorMessage = "Failed to read CSV file."
                return
            }
            let count = DatabaseService.shared.importLeadsFromCSV(csv)
            // Reload leads from DB after import
            leads = DatabaseService.shared.loadLeads()
            if count > 0 {
                statusMessage = "\(count) leads imported from \(url.lastPathComponent)"
            } else {
                errorMessage = "No leads imported. Check CSV format."
            }
        }
        #endif
    }

    // MARK: - Import Companies from CSV
    func importCompaniesFromCSV() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.title = "Import Companies from CSV"
        panel.message = "Select a CSV file to import companies."
        if panel.runModal() == .OK, let url = panel.url {
            guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
                errorMessage = "Failed to read CSV file."
                return
            }
            let count = DatabaseService.shared.importCompaniesFromCSV(csv)
            // Reload companies from DB after import
            companies = DatabaseService.shared.loadCompanies()
            if count > 0 {
                statusMessage = "\(count) companies imported from \(url.lastPathComponent)"
            } else {
                errorMessage = "No companies imported. Check CSV format."
            }
        }
        #endif
    }

    // MARK: - URL-based variants (for use in tests / drag-and-drop)
    @discardableResult
    func importLeadsFromCSV(url: URL) -> Int {
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let count = DatabaseService.shared.importLeadsFromCSV(csv)
        leads = DatabaseService.shared.loadLeads()
        return count
    }

    @discardableResult
    func importCompaniesFromCSV(url: URL) -> Int {
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let count = DatabaseService.shared.importCompaniesFromCSV(csv)
        companies = DatabaseService.shared.loadCompanies()
        return count
    }

    func exportLeadsCSV(to url: URL) {
        let csv = DatabaseService.shared.exportLeadsCSV()
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportCompaniesCSV(to url: URL) {
        let csv = DatabaseService.shared.exportCompaniesCSV()
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
