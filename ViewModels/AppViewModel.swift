import Foundation
import Combine
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Services
    let authService = GoogleAuthService()
    private var authCancellable: AnyCancellable?
    private let pplxService = PerplexityService()
    private lazy var gmailService = GmailService(authService: authService)
    private lazy var sheetsService = GoogleSheetsService(authService: authService)

    // MARK: - Constants
    static let senderEmail = "mf@harpocrates-corp.com"

    // MARK: - State
    @Published var settings = AppSettings()
    @Published var companies: [Company] = []
    @Published var leads: [Lead] = []
    @Published var replies: [GmailService.GmailMessage] = []
    @Published var sheetData: [[String]] = []
        @Published var socialPosts: [SocialPost] = []

    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage = ""
    @Published var currentStep = ""

    private let saveURL: URL
    private let companiesSaveURL: URL
        private let socialPostsSaveURL: URL
    private var currentTask: Task<Void, Never>?

    // MARK: - Init
    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach",
            isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir,
            withIntermediateDirectories: true)
        self.saveURL = appDir.appendingPathComponent("leads.json")
        self.companiesSaveURL = appDir.appendingPathComponent("companies.json")
                self.socialPostsSaveURL = appDir.appendingPathComponent("socialPosts.json")
        loadSettings()
        loadLeads()
        loadCompanies()
                loadSocialPosts()
        configureAuth()
        authCancellable = authService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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
        // Sheet automatisch initialisieren wenn Spreadsheet-ID vorhanden
        if !settings.spreadsheetID.isEmpty {
            Task {
                do {
                    try await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID)
                    print("[Sheets] Sheet initialisiert")
                } catch {
                    print("[Sheets] Init FEHLER: \(error.localizedDescription)")
                    errorMessage = "Sheet-Init: \(error.localizedDescription)"
                }
            }
        }
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

        let industries = Industry.allCases.filter { settings.selectedIndustries.contains($0.rawValue) }
        let regions = Region.allCases.filter { settings.selectedRegions.contains($0.rawValue) }

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
                    errorMessage = "Fehler \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)"
                }
            }
        }
        currentStep = "\(companies.count) Unternehmen gefunden"
        saveCompanies()
        isLoading = false
    }

    // MARK: - 2) Kontakte finden (Schritt 2)
    func findContacts(for company: Company) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true
        currentStep = "Suche Compliance-Kontakte bei \(company.name)..."
        do {
            let found = try await pplxService.findContacts(company: company, apiKey: settings.perplexityAPIKey)
            let newLeads = found.filter { newLead in
                !leads.contains { $0.name.lowercased() == newLead.name.lowercased() && $0.company.lowercased() == newLead.company.lowercased() }
            }
            leads.append(contentsOf: newLeads)
            saveLeads()
            currentStep = "\(newLeads.count) Kontakte bei \(company.name) gefunden"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    func findContactsForAll() async {
        for company in companies { await findContacts(for: company) }
    }

    // MARK: - 3) Email verifizieren (Schritt 3)
    func verifyEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        isLoading = true
        currentStep = "Verifiziere Email fuer \(leads[idx].name)..."
        do {
            let result = try await pplxService.verifyEmail(lead: leads[idx], apiKey: settings.perplexityAPIKey)
            leads[idx].email = result.email
            leads[idx].emailVerified = result.verified
            leads[idx].verificationNotes = result.notes
            leads[idx].status = result.verified ? .contacted : .identified
            saveLeads()
            currentStep = result.verified ? "Email verifiziert: \(result.email)" : "Email nicht verifiziert: \(result.notes)"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    func verifyAllEmails() async {
        let unverified = leads.filter { !$0.emailVerified }
        for lead in unverified { await verifyEmail(for: lead.id) }
    }

    // MARK: - 4) Recherche + Email Draft (Schritt 4+5)
    func draftEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        guard leads[idx].emailVerified || leads[idx].isManuallyCreated else { errorMessage = "Email muss zuerst verifiziert sein."; return }
        isLoading = true
        currentStep = "Recherchiere Challenges fuer \(leads[idx].company)..."
        do {
            let companyForResearch = companies.first { $0.name.lowercased() == leads[idx].company.lowercased() } ?? Company(name: leads[idx].company, industry: "", region: "")
            let challenges = try await pplxService.researchChallenges(
                company: companyForResearch, apiKey: settings.perplexityAPIKey)
            currentStep = "Erstelle personalisierte Email fuer \(leads[idx].name)..."
            let email = try await pplxService.draftEmail(
                lead: leads[idx], challenges: challenges,
                senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].draftedEmail = email
            leads[idx].status = .emailDrafted
            saveLeads()
            currentStep = "Email-Entwurf erstellt fuer \(leads[idx].name)"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    func draftAllEmails() async {
        let verified = leads.filter { $0.emailVerified && $0.draftedEmail == nil }
        for lead in verified { await draftEmail(for: lead.id) }
    }

    func initializeSheet() async {
        guard !settings.spreadsheetID.isEmpty else { return }
        do {
            try await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID)
            print("[Sheets] Sheet initialisiert")
        } catch {
            print("[Sheets] Init FEHLER: \(error.localizedDescription)")
            errorMessage = "Sheet-Init: \(error.localizedDescription)"
        }
    }

    // MARK: - Lead loeschen
    func deleteLead(_ leadID: UUID) {
        leads.removeAll { $0.id == leadID }
        saveLeads()
    }

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
        if let data = try? JSONEncoder().encode(leads) { try? data.write(to: saveURL) }
    }
    private func loadLeads() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Lead].self, from: data) else { return }
        leads = saved
    }
    private func saveCompanies() {
        if let data = try? JSONEncoder().encode(companies) { try? data.write(to: companiesSaveURL) }
    }
    private func loadCompanies() {
        guard let data = try? Data(contentsOf: companiesSaveURL),
              let saved = try? JSONDecoder().decode([Company].self, from: data) else { return }
        companies = saved
    }

    // MARK: - 5) Email freigeben
    func approveEmail(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].draftedEmail?.isApproved = true
        leads[idx].status = .emailApproved
        saveLeads()
    }

    // MARK: - 6) Email senden (Sender: mf@harpocrates-corp.com)
    func sendEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let email = leads[idx].draftedEmail, email.isApproved else {
            errorMessage = "Email muss zuerst freigegeben werden."
            return
        }
        isLoading = true
        currentStep = "Sende Email an \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email, from: Self.senderEmail,
                subject: email.subject, body: email.body)
            leads[idx].dateEmailSent = Date()
            leads[idx].draftedEmail?.sentDate = Date()
            leads[idx].status = .emailSent
            saveLeads()
            // Google Sheets Logging mit Fehlerausgabe
            if !settings.spreadsheetID.isEmpty {
                do {
                    try await sheetsService.logEmailEvent(
                        spreadsheetID: settings.spreadsheetID,
                        lead: leads[idx], emailType: "Erstversand",
                        subject: email.subject, body: email.body,
                        summary: "Outreach-Email an \(leads[idx].name) (\(leads[idx].company)) gesendet")
                    print("[Sheets] Email-Event geloggt fuer \(leads[idx].name)")
                } catch {
                    print("[Sheets] Log FEHLER: \(error.localizedDescription)")
                    errorMessage = "Sheet-Logging: \(error.localizedDescription)"
                }
            }
            currentStep = "Email gesendet an \(leads[idx].email)"
        } catch {
            errorMessage = "Senden fehlgeschlagen: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - 7) Antworten pruefen (Subject + Email-basiert)
    func checkForReplies() async {
        // Sammle alle Subjects von gesendeten Emails
        var sentSubjects: [String] = []
        for lead in leads {
            if lead.dateEmailSent != nil, let subj = lead.draftedEmail?.subject, !subj.isEmpty {
                sentSubjects.append(subj)
            }
            if lead.dateFollowUpSent != nil, let subj = lead.followUpEmail?.subject, !subj.isEmpty {
                sentSubjects.append(subj)
            }
        }
        let uniqueSubjects = Array(Set(sentSubjects))
        let sentLeadEmails = leads.filter { $0.dateEmailSent != nil || $0.dateFollowUpSent != nil }.map { $0.email }
        guard !uniqueSubjects.isEmpty else {
            statusMessage = "Keine gesendeten Emails zum Pruefen."
            return
        }
        isLoading = true
        currentStep = "Pruefe Posteingang auf Antworten..."
        do {
            let found = try await gmailService.checkReplies(sentSubjects: uniqueSubjects, leadEmails: sentLeadEmails)
            replies = found
            print("[CheckReplies] \(found.count) Antworten von Gmail erhalten")

            for reply in found {
                let replyFrom = reply.from.lowercased()
                let replySubject = reply.subject.lowercased()
                    .replacingOccurrences(of: "re: ", with: "")
                    .replacingOccurrences(of: "aw: ", with: "")
                    .replacingOccurrences(of: "fwd: ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                var matchedIdx: Int?

                // 1. Subject-Match: Vergleiche mit Wort-Ueberlappung statt exaktem contains
                matchedIdx = leads.firstIndex(where: { lead in
                    if let draftSubj = lead.draftedEmail?.subject, !draftSubj.isEmpty {
                        let cleanDraft = draftSubj.lowercased()
                            .replacingOccurrences(of: "re: ", with: "")
                            .replacingOccurrences(of: "aw: ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        // Bidirektionaler contains-Check
                        if replySubject.contains(cleanDraft) || cleanDraft.contains(replySubject) {
                            return true
                        }
                        // Wort-basierter Vergleich als Fallback
                        let draftWords = Set(cleanDraft.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        let replyWords = Set(replySubject.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        let overlap = draftWords.intersection(replyWords)
                        if !draftWords.isEmpty && Double(overlap.count) / Double(draftWords.count) > 0.5 {
                            return true
                        }
                    }
                    if let followUpSubj = lead.followUpEmail?.subject, !followUpSubj.isEmpty {
                        let cleanFollowUp = followUpSubj.lowercased()
                            .replacingOccurrences(of: "re: ", with: "")
                            .replacingOccurrences(of: "aw: ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if replySubject.contains(cleanFollowUp) || cleanFollowUp.contains(replySubject) {
                            return true
                        }
                    }
                    return false
                })

                // 2. Email-Match als Fallback
                if matchedIdx == nil {
                    matchedIdx = leads.firstIndex(where: { lead in
                        !lead.email.isEmpty && replyFrom.contains(lead.email.lowercased())
                            && (lead.dateEmailSent != nil || lead.dateFollowUpSent != nil)
                    })
                    if matchedIdx != nil {
                        print("[CheckReplies] Email-basierter Match fuer: \(reply.from)")
                    }
                }

                if let idx = matchedIdx {
                    leads[idx].replyReceived = reply.snippet
                    leads[idx].status = .replied
                    print("[CheckReplies] Antwort zugeordnet: \(leads[idx].name) (\(leads[idx].company))")

                    // Google Sheets Logging
                    if !settings.spreadsheetID.isEmpty {
                        do {
                            try await sheetsService.logReplyReceived(
                                spreadsheetID: settings.spreadsheetID,
                                lead: leads[idx], replySubject: reply.subject,
                                replySnippet: reply.snippet, replyFrom: reply.from)
                            print("[CheckReplies] Sheet-Log erfolgreich fuer \(leads[idx].name)")
                        } catch {
                            print("[CheckReplies] Sheet-Log FEHLER: \(error.localizedDescription)")
                            errorMessage = "Sheet-Logging fehlgeschlagen: \(error.localizedDescription)"
                        }
                    }
                } else {
                    print("[CheckReplies] Kein Lead-Match fuer Reply von: \(reply.from) - \(reply.subject)")
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
                followUpEmail: leads[idx].followUpEmail?.body ?? "",
                replyReceived: leads[idx].replyReceived,
                senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].followUpEmail = followUp
            leads[idx].status = .followUpDrafted
            saveLeads()
            currentStep = "Follow-Up erstellt fuer \(leads[idx].name)"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    func approveFollowUp(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].followUpEmail?.isApproved = true
        saveLeads()
    }

    func sendFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let followUp = leads[idx].followUpEmail, followUp.isApproved else {
            errorMessage = "Follow-Up muss zuerst freigegeben werden."
            return
        }
        isLoading = true
        currentStep = "Sende Follow-Up an \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email, from: Self.senderEmail,
                subject: followUp.subject, body: followUp.body)
            leads[idx].dateFollowUpSent = Date()
            leads[idx].followUpEmail?.sentDate = Date()
            leads[idx].status = .followUpSent
            saveLeads()
            // Google Sheets Logging
            if !settings.spreadsheetID.isEmpty {
                do {
                    try await sheetsService.logEmailEvent(
                        spreadsheetID: settings.spreadsheetID,
                        lead: leads[idx], emailType: "Follow-Up",
                        subject: followUp.subject, body: followUp.body,
                        summary: "Follow-Up an \(leads[idx].name) (\(leads[idx].company)) gesendet")
                    print("[Sheets] Follow-Up geloggt fuer \(leads[idx].name)")
                } catch {
                    print("[Sheets] Follow-Up Log FEHLER: \(error.localizedDescription)")
                    errorMessage = "Sheet-Logging: \(error.localizedDescription)"
                }
            }
            currentStep = "Follow-Up gesendet an \(leads[idx].email)"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - Google Sheets lesen
    func refreshSheetData() async {
        guard !settings.spreadsheetID.isEmpty else { errorMessage = "Spreadsheet ID fehlt."; return }
        isLoading = true
        do {
            sheetData = try await sheetsService.readAllLeads(spreadsheetID: settings.spreadsheetID)
            currentStep = "\(sheetData.count) Zeilen aus Sheet geladen"
            print("[Sheets] \(sheetData.count) Zeilen gelesen")
        } catch {
            errorMessage = "Sheet Fehler: \(error.localizedDescription)"
            print("[Sheets] Read FEHLER: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Cancel Operations
    func cancelOperation() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        currentStep = ""
        statusMessage = "Operation cancelled"
    }

    // MARK: - Manual Entry
    func addCompanyManually(_ company: Company) {
        if !companies.contains(where: { $0.name.lowercased() == company.name.lowercased() }) {
            companies.append(company)
            statusMessage = "Unternehmen \(company.name) manuell hinzugefuegt"
        } else { errorMessage = "Unternehmen \(company.name) existiert bereits" }
    }

    func addLeadManually(_ lead: Lead) {
        if !leads.contains(where: { $0.name.lowercased() == lead.name.lowercased() && $0.company.lowercased() == lead.company.lowercased() }) {
            leads.append(lead)
            saveLeads()
            statusMessage = "Kontakt \(lead.name) manuell hinzugefuegt"
        } else { errorMessage = "Kontakt \(lead.name) bei \(lead.company) existiert bereits" }
    }

    // MARK: - Test Mode
    func addTestCompany() {
        let testCompany = Company(
            name: "Harpocrates Corp", industry: "K - Finanzdienstleistungen",
            region: "DACH", website: "https://harpocrates-corp.com",
            description: "RegTech Startup fuer Compliance Management")
        if !companies.contains(where: { $0.name == "Harpocrates Corp" }) {
            companies.append(testCompany)
            statusMessage = "Testfirma Harpocrates hinzugefuegt"
        }
        let testLead = Lead(
            name: "Martin Foerster", title: "CEO & Founder",
            company: testCompany.name, email: "mf@harpocrates-corp.com",
            emailVerified: true, linkedInURL: "https://linkedin.com/in/martinfoerster",
            status: .contacted, source: "test")
        if !leads.contains(where: { $0.email == "mf@harpocrates-corp.com" }) {
            leads.append(testLead)
            saveLeads()
            statusMessage = "Testkontakt Martin Foerster hinzugefuegt"
        }
    }

    // MARK: - Draft Management
    func updateDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = OutboundEmail(
                id: lead.draftedEmail?.id ?? UUID(),
                subject: subject, body: body, isApproved: true)
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
        guard let draft = lead.draftedEmail else { errorMessage = "Kein Draft vorhanden fuer \(lead.name)"; return }
        guard !lead.email.isEmpty else { errorMessage = "Keine Email-Adresse fuer \(lead.name)"; return }
        guard authService.isAuthenticated else {
            errorMessage = "Nicht bei Google angemeldet. Bitte unter Einstellungen mit Google anmelden."
            return
        }
        print("[SendEmail] Sende an: \(lead.email), von: \(Self.senderEmail), Betreff: \(draft.subject)")
        isLoading = true
        errorMessage = ""
        currentStep = "Sende Email an \(lead.name)..."
        do {
            _ = try await gmailService.sendEmail(
                to: lead.email, from: Self.senderEmail,
                subject: draft.subject, body: draft.body)
            if let index = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[index].status = .emailSent
                leads[index].dateEmailSent = Date()
                leads[index].draftedEmail?.sentDate = Date()
                saveLeads()
                // Google Sheets Logging mit Fehlerausgabe
                if !settings.spreadsheetID.isEmpty {
                    do {
                        try await sheetsService.logEmailEvent(
                            spreadsheetID: settings.spreadsheetID,
                            lead: leads[index], emailType: "Erstversand",
                            subject: draft.subject, body: draft.body,
                            summary: "Outreach-Email an \(lead.name) (\(lead.company)) gesendet")
                        print("[Sheets] Email-Event geloggt fuer \(lead.name)")
                    } catch {
                        print("[Sheets] Log FEHLER: \(error.localizedDescription)")
                        errorMessage = "Sheet-Logging: \(error.localizedDescription)"
                    }
                }
            }
            statusMessage = "Email an \(lead.name) erfolgreich gesendet"
            print("[SendEmail] Erfolgreich gesendet an \(lead.email)")
        } catch {
            errorMessage = "Senden fehlgeschlagen: \(error.localizedDescription)"
            print("[SendEmail] FEHLER: \(error)")
        }
        isLoading = false
        currentStep = ""
    }

    // MARK: - Email Sent Count
    func emailSentCount(for lead: Lead) -> Int {
        var count = 0
        if lead.dateEmailSent != nil { count += 1 }
        if lead.dateFollowUpSent != nil { count += 1 }
        return count
    }

    // MARK: - Follow-Up aus Kontaktliste
    func draftFollowUpFromContact(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        let lead = leads[idx]
        guard lead.dateEmailSent != nil else {
            errorMessage = "Erst eine Email senden bevor Follow-Up moeglich ist."
            return
        }
        if lead.followUpEmail != nil {
            statusMessage = "Follow-Up Draft existiert bereits fuer \(lead.name). Siehe Outbox."
            return
        }
        guard let originalEmail = lead.draftedEmail else {
            errorMessage = "Kein Original-Draft vorhanden fuer \(lead.name)"
            return
        }
        isLoading = true
        currentStep = "Erstelle Follow-Up fuer \(lead.name)..."
        do {
            let followUp = try await pplxService.draftFollowUp(
                lead: lead, originalEmail: originalEmail.body,
                followUpEmail: lead.followUpEmail?.body ?? "",
                replyReceived: lead.replyReceived,
                senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].followUpEmail = followUp
            leads[idx].status = .followUpDrafted
            saveLeads()
            currentStep = "Follow-Up erstellt fuer \(leads[idx].name)"
        } catch { errorMessage = "Fehler: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - Quick Draft fuer Kontakt
    func quickDraftAndShowInOutbox(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        if leads[idx].draftedEmail == nil {
            await draftEmail(for: leadID)
        }
        if leads[idx].draftedEmail != nil && leads[idx].draftedEmail?.isApproved == false {
            leads[idx].draftedEmail?.isApproved = true
            leads[idx].status = .emailApproved
            saveLeads()
        }
    }

    // MARK: - Follow-Up Draft Management
    func updateFollowUpDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = OutboundEmail(
                id: lead.followUpEmail?.id ?? UUID(),
                subject: subject, body: body, isApproved: true)
            saveLeads()
            statusMessage = "Follow-Up Draft fuer \(lead.name) aktualisiert"
        }
    }

    func deleteFollowUpDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = nil
            leads[index].status = .emailSent
            saveLeads()
            statusMessage = "Follow-Up Draft fuer \(lead.name) geloescht"
        }
    }

    // MARK: - Datenbasis bereinigen
    func purgeAllExcept(companyName: String) {
        let keepName = companyName.lowercased()
        let beforeLeads = leads.count
        let beforeCompanies = companies.count
        leads = leads.filter { $0.company.lowercased().contains(keepName) }
        companies = companies.filter { $0.name.lowercased().contains(keepName) }
        saveLeads()
        saveCompanies()
        replies = []
        let removedLeads = beforeLeads - leads.count
        let removedCompanies = beforeCompanies - companies.count
        statusMessage = "Bereinigt: \(removedLeads) Leads und \(removedCompanies) Unternehmen geloescht. Behalten: \(leads.count) Leads, \(companies.count) Unternehmen."
    }

    // MARK: - Social Post Generation
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform = .linkedin, industries: [String] = []) async {
        guard !settings.perplexityAPIKey.isEmpty else {
            errorMessage = "Perplexity API Key fehlt."
            return
        }
        isLoading = true
        currentStep = "Generiere \(platform.rawValue) Post..."
        do {
            var post = try await pplxService.generateSocialPost(
                topic: topic,
                platform: platform,
                industries: industries.isEmpty ? settings.selectedIndustries : industries,
                existingPosts: socialPosts,
                apiKey: settings.perplexityAPIKey)
                                // Safety net: Footer MUSS immer dabei sein
                                post.content = PerplexityService.ensureFooter(post.content)
            socialPosts.insert(post, at: 0)
            saveSocialPosts()
            currentStep = "Post erstellt"
        } catch {
            errorMessage = "Post-Generierung fehlgeschlagen: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func deleteSocialPost(_ postID: UUID) {
        socialPosts.removeAll { $0.id == postID }
        saveSocialPosts()
    }

    func updateSocialPost(_ post: SocialPost) {
        if let idx = socialPosts.firstIndex(where: { $0.id == post.id }) {
            socialPosts[idx] = post
            saveSocialPosts()
        }
    }

    func copyPostToClipboard(_ post: SocialPost) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(post.content, forType: .string)
        statusMessage = "Post in Zwischenablage kopiert"
        #endif
    }

    private func saveSocialPosts() {
        if let data = try? JSONEncoder().encode(socialPosts) {
            try? data.write(to: socialPostsSaveURL)
        }
    }

    private func loadSocialPosts() {
        guard let data = try? Data(contentsOf: socialPostsSaveURL),
              let saved = try? JSONDecoder().decode([SocialPost].self, from: data) else { return }
        socialPosts = saved
    }
}
