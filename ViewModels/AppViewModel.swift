import Foundation
import Combine
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Services
    let authService = GoogleAuthService()
    private let pplxService = PerplexityService()
    private lazy var gmailService = GmailService(authService: authService)
    private lazy var sheetsService = GoogleSheetsService(authService: authService)

    // MARK: - State
    @Published var settings = AppSettings()
    @Published var companies: [Company] = []
    @Published var leads: [Lead] = []
    @Published var replies: [GmailService.GmailMessage] = []
    @Published var sheetData: [[String]] = []

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""
    @Published var currentStep = ""

    private let saveURL: URL

    // MARK: - Init
    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = appDir.appendingPathComponent("leads.json")
        loadSettings()
        loadLeads()
        configureAuth()
    }

    private func configureAuth() {
        authService.configure(clientID: settings.googleClientID,
                              clientSecret: settings.googleClientSecret)
    }

    // MARK: - Settings
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "harpo_settings")
        }
        configureAuth()
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "harpo_settings"),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        }
    }

    // MARK: - 1) Unternehmen finden (Schritt 1)
    func findCompanies() async {
        guard !settings.perplexityAPIKey.isEmpty else {
            errorMessage = "Perplexity API Key fehlt. Bitte in Einstellungen eintragen."
            return
        }
        isLoading = true
        errorMessage = ""
        companies = []

        let industries = Industry.allCases.filter {
            settings.selectedIndustries.contains($0.rawValue)
        }
        let regions = Region.allCases.filter {
            settings.selectedRegions.contains($0.rawValue)
        }

        for industry in industries {
            for region in regions {
                currentStep = "Suche \(industry.rawValue) Unternehmen in \(region.rawValue)..."
                do {
                    let found = try await pplxService.findCompanies(
                        industry: industry, region: region,
                        apiKey: settings.perplexityAPIKey)
                    let newOnes = found.filter { new in
                        !companies.contains { $0.name.lowercased() == new.name.lowercased() }
                    }
                    companies.append(contentsOf: newOnes)
                } catch {
                    statusMessage = "Fehler \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)"
                }
            }
        }
        currentStep = "\(companies.count) Unternehmen gefunden"
        isLoading = false
    }

    // MARK: - 2) Kontakte finden (Schritt 2)
    func findContacts(for company: Company) async {
        guard !settings.perplexityAPIKey.isEmpty else {
            errorMessage = "Perplexity API Key fehlt."
            return
        }
        isLoading = true
        currentStep = "Suche Compliance-Kontakte bei \(company.name)..."

        do {
            let found = try await pplxService.findContacts(
                company: company, apiKey: settings.perplexityAPIKey)
            let newLeads = found.filter { newLead in
                !leads.contains { $0.name.lowercased() == newLead.name.lowercased()
                    && $0.company.lowercased() == newLead.company.lowercased() }
            }
            leads.append(contentsOf: newLeads)
            saveLeads()
            currentStep = "\(newLeads.count) Kontakte bei \(company.name) gefunden"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func findContactsForAll() async {
        for company in companies {
            await findContacts(for: company)
        }
    }

    // MARK: - 3) Email verifizieren (Schritt 3)
    func verifyEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        isLoading = true
        currentStep = "Verifiziere Email fuer \(leads[idx].name)..."

        do {
            let result = try await pplxService.verifyEmail(
                lead: leads[idx], apiKey: settings.perplexityAPIKey)
            leads[idx].email = result.email
            leads[idx].emailVerified = result.verified
            leads[idx].verificationNotes = result.notes
            leads[idx].status = result.verified ? .contacted : .identified
            saveLeads()
            currentStep = result.verified
                ? "Email verifiziert: \(result.email)"
                : "Email nicht verifiziert: \(result.notes)"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func verifyAllEmails() async {
        let unverified = leads.filter { !$0.emailVerified }
        for lead in unverified {
            await verifyEmail(for: lead.id)
        }
    }

    // MARK: - 4) Recherche + Email Draft (Schritt 4+5)
    func draftEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        guard leads[idx].emailVerified else {
            errorMessage = "Email muss zuerst verifiziert sein."
            return
        }
        isLoading = true
        currentStep = "Recherchiere Challenges fuer \(leads[idx].company)..."

        do {
            // Schritt 4: Challenges recherchieren
            // let challenges = try await pplxService.researchChallenges(
//                                    company: leads[idx].company, apiKey: settings.perplexityAPIKey)
            

            // Schritt 5: Email drafting
            currentStep = "Erstelle personalisierte Email fuer \(leads[idx].name)..."
            let email = try await pplxService.draftEmail(
                lead: leads[idx], challenges: "",
                senderName: settings.senderName,
                apiKey: settings.perplexityAPIKey)
            leads[idx].draftedEmail = email
            leads[idx].status = .emailDrafted
            saveLeads()
            currentStep = "Email-Entwurf erstellt fuer \(leads[idx].name)"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func draftAllEmails() async {
        let verified = leads.filter { $0.emailVerified && $0.draftedEmail == nil }
        for lead in verified {
            await draftEmail(for: lead.id)
        }
    }
    func initializeSheet() async {
        guard !settings.spreadsheetID.isEmpty else { return }
        try? await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID)
    }

    // MARK: - Lead loeschen
    func deleteLead(_ leadID: UUID) {
        leads.removeAll { $0.id == leadID }
        saveLeads()
    }

    // MARK: - Lead manuell bearbeiten
    func updateLead(_ lead: Lead) {
        if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[idx] = lead
            saveLeads()
        }
    }

    // MARK: - Statistiken
    var statsIdentified: Int { leads.count }
    var statsVerified: Int { leads.filter { $0.emailVerified }.count }
    var statsSent: Int { leads.filter { $0.dateEmailSent != nil }.count }
    var statsReplied: Int { leads.filter { !$0.replyReceived.isEmpty }.count }
    var statsFollowUp: Int { leads.filter { $0.dateFollowUpSent != nil }.count }

    // MARK: - Persistenz
    private func saveLeads() {
        if let data = try? JSONEncoder().encode(leads) {
            try? data.write(to: saveURL)
        }
    }

    private func loadLeads() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Lead].self, from: data)
        else { return }
        leads = saved
    }
    // MARK: - 5) Email freigeben
    func approveEmail(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].draftedEmail?.isApproved = true
        leads[idx].status = .emailApproved
        saveLeads()
    }

    // MARK: - 6) Email senden
    func sendEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let email = leads[idx].draftedEmail,
              email.isApproved else {
            errorMessage = "Email muss zuerst freigegeben werden."
            return
        }
        isLoading = true
        currentStep = "Sende Email an \(leads[idx].email)..."

        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email,
                from: settings.senderEmail,
                subject: email.subject,
                body: email.body)
            leads[idx].dateEmailSent = Date()
            leads[idx].draftedEmail?.sentDate = Date()
            leads[idx].status = .emailSent
            saveLeads()

            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.logLead(
                    spreadsheetID: settings.spreadsheetID, lead: leads[idx])
            }
            currentStep = "Email gesendet an \(leads[idx].email)"
        } catch {
            errorMessage = "Senden fehlgeschlagen: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - 7) Antworten pruefen
    func checkForReplies() async {
        let sentEmails = leads.filter { $0.status == .emailSent || $0.status == .followUpSent }
            .compactMap { $0.email.isEmpty ? nil : $0.email }
        guard !sentEmails.isEmpty else {
            statusMessage = "Keine gesendeten Emails zum Pruefen."
            return
        }
        isLoading = true
        currentStep = "Pruefe Posteingang auf Antworten..."

        do {
            let found = try await gmailService.checkReplies(sentToEmails: sentEmails)
            replies = found

            for reply in found {
                let fromEmail = reply.from.lowercased()
                if let idx = leads.firstIndex(where: {
                    fromEmail.contains($0.email.lowercased()) }) {
                    leads[idx].replyReceived = reply.snippet
                    leads[idx].status = .replied
                    if !settings.spreadsheetID.isEmpty {
                        try? await sheetsService.updateLead(
                            spreadsheetID: settings.spreadsheetID, lead: leads[idx])
                    }
                }
            }
            saveLeads()
            currentStep = "\(found.count) Antworten gefunden"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - 8) Follow-Up
    func checkFollowUpsNeeded() -> [Lead] {
        let calendar = Calendar.current
        return leads.filter { lead in
            guard lead.status == .emailSent,
                  let sentDate = lead.dateEmailSent,
                  lead.replyReceived.isEmpty,
                  lead.followUpEmail == nil else { return false }
            let daysSince = calendar.dateComponents([.day], from: sentDate, to: Date()).day ?? 0
            return daysSince >= 14
        }
    }

    func draftFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let originalEmail = leads[idx].draftedEmail else { return }
        isLoading = true
        currentStep = "Erstelle Follow-Up fuer \(leads[idx].name)..."

        do {
            let followUp = try await pplxService.draftFollowUp(
                lead: leads[idx], originalEmail: originalEmail.body,
                senderName: settings.senderName,
                apiKey: settings.perplexityAPIKey)
            leads[idx].followUpEmail = followUp
            leads[idx].status = .followUpDrafted
            saveLeads()
            currentStep = "Follow-Up erstellt fuer \(leads[idx].name)"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func approveFollowUp(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].followUpEmail?.isApproved = true
        saveLeads()
    }

    func sendFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let followUp = leads[idx].followUpEmail,
              followUp.isApproved else {
            errorMessage = "Follow-Up muss zuerst freigegeben werden."
            return
        }
        isLoading = true
        currentStep = "Sende Follow-Up an \(leads[idx].email)..."

        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email,
                from: settings.senderEmail,
                subject: followUp.subject,
                body: followUp.body)
            leads[idx].dateFollowUpSent = Date()
            leads[idx].followUpEmail?.sentDate = Date()
            leads[idx].status = .followUpSent
            saveLeads()

            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.updateLead(
                    spreadsheetID: settings.spreadsheetID, lead: leads[idx])
            }
            currentStep = "Follow-Up gesendet an \(leads[idx].email)"
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Google Sheets lesen
    func refreshSheetData() async {
        guard !settings.spreadsheetID.isEmpty else {
            errorMessage = "Spreadsheet ID fehlt."
            return
        }
        isLoading = true
        do {
            sheetData = try await sheetsService.readAllLeads(
                spreadsheetID: settings.spreadsheetID)
            currentStep = "\(sheetData.count) Zeilen aus Sheet geladen"
        } catch {
            errorMessage = "Sheet Fehler: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // MARK: - Cancel Operations
    func cancelOperation() {
        isLoading = false
        currentStep = ""
        statusMessage = "Operation cancelled"
    }
    
    // MARK: - Manual Entry
    func addCompanyManually(_ company: Company) {
        // Check for duplicates
        if !companies.contains(where: { $0.name.lowercased() == company.name.lowercased() }) {
            companies.append(company)
            statusMessage = "Unternehmen \(company.name) manuell hinzugefügt"
        } else {
            errorMessage = "Unternehmen \(company.name) existiert bereits"
        }
    }
    
    func addLeadManually(_ lead: Lead) {
        // Check for duplicates
        if !leads.contains(where: { 
            $0.name.lowercased() == lead.name.lowercased() &&
            $0.company.lowercased() == lead.company.lowercased()
        }) {
            leads.append(lead)
            saveLeads()
            statusMessage = "Kontakt \(lead.name) manuell hinzugefügt"
        } else {
            errorMessage = "Kontakt \(lead.name) bei \(lead.company) existiert bereits"
        }
    }

    
    // MARK: - Test Mode
    func addTestCompany() {
        let testCompany = Company(
            name: "Harpocrates Corp",
            industry: "Financial Services",
            region: "DACH",
            website: "https://harpocrates-corp.com",
            description: "RegTech Startup für Compliance Management",
        )
        
        if !companies.contains(where: { $0.name == "Harpocrates Corp" }) {
            companies.append(testCompany)
            statusMessage = "Testfirma Harpocrates hinzugefügt"
        }
        
        let testLead = Lead(
            name: "Martin Förster",
            title: "CEO & Founder",
            company: testCompany,
            email: "mf@harpocrates-corp.com",
            emailVerified: true,
            linkedInURL: "https://linkedin.com/in/martinfoerster",
            status: .contacted,
            source: "test"
        )
        
        if !leads.contains(where: { $0.email == "mf@harpocrates-corp.com" }) {
            leads.append(testLead)
            saveLeads()
            statusMessage = "Testkontakt Martin Förster hinzugefügt"
        }
    }

            // MARK: - Draft Management
    
    func updateDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = OutboundEmail(
                id: lead.draftedEmail?.id ?? UUID(),
                subject: subject,
                body: body,
                isApproved: true
            )
            saveLeads()
            statusMessage = "Draft fuer \(lead.name) aktualisiert"
        }
    }
    
    func deleteDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = nil
            saveLeads()
            statusMessage = "Draft fuer \(lead.name) geloescht"
        }
    }
    
    func sendEmail(to lead: Lead) async {
        guard let draft = lead.draftedEmail else {
            errorMessage = "Kein Draft vorhanden fuer \(lead.name)"
            return
        }
        
        isLoading = true
        currentStep = "Sende Email an \(lead.name)..."
        
        do {
            try await gmailService.sendEmail(
                to: lead.email,
                            from: settings.senderEmail,
                subject: draft.subject,
                body: draft.body
            )
            
            // Update lead status
            if let index = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[index].status = .contacted
                leads[index].dateEmailSent = Date()
                // Draft nach Versand entfernen
                leads[index].draftedEmail = nil
                saveLeads()
            }
            
            statusMessage = "Email an \(lead.name) erfolgreich gesendet"
        } catch {
            errorMessage = "Fehler beim Senden: \(error.localizedDescription)"
        }
        
        isLoading = false
        currentStep = ""
    }



}

