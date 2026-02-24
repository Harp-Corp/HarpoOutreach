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

    // NEW: Industry filter for Prospecting search
    @Published var selectedIndustryFilter: Industry?
    // NEW: Per-search contact results (only current search)
    @Published var currentSearchContacts: [Lead] = []

    private let saveURL: URL
    private let companiesSaveURL: URL
    private let socialPostsSaveURL: URL
    private var currentTask: Task<Void, Never>?

    // MARK: - Init
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = appDir.appendingPathComponent("leads.json")
        self.companiesSaveURL = appDir.appendingPathComponent("companies.json")
        self.socialPostsSaveURL = appDir.appendingPathComponent("socialPosts.json")
        loadSettings(); loadLeads(); loadCompanies(); loadSocialPosts(); migrateSocialPostFooters(); configureAuth()
        authCancellable = authService.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func configureAuth() {
        authService.configure(clientID: settings.googleClientID, clientSecret: settings.googleClientSecret)
    }

    // MARK: - Settings
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "harpo_settings") }
        configureAuth()
        if !settings.spreadsheetID.isEmpty {
            Task {
                do { try await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID) }
                catch { errorMessage = "Sheet-Init: \(error.localizedDescription)" }
            }
        }
    }

    private func loadSettings() {
        let defaults = AppSettings()
        if let data = UserDefaults.standard.data(forKey: "harpo_settings"),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        }
        // Migrate: force new credentials if stored ones are empty or outdated
        let validClientSuffix = "mrurpt9kdelunlaqqklg4ib8arkv16pc"
        if settings.googleClientID.isEmpty || !settings.googleClientID.contains(validClientSuffix) {
            settings.googleClientID = defaults.googleClientID
            settings.googleClientSecret = defaults.googleClientSecret
            saveSettings()
        }
        if settings.perplexityAPIKey.isEmpty {
            settings.perplexityAPIKey = defaults.perplexityAPIKey
            saveSettings()
        }
    }
    // MARK: - 1) Unternehmen finden (with optional industry filter)
    func findCompanies(forIndustry: Industry? = nil) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true; errorMessage = ""; companies = []
        let industries: [Industry]
        if let specific = forIndustry ?? selectedIndustryFilter {
            industries = [specific]
        } else {
            industries = Industry.allCases.filter { settings.selectedIndustries.contains($0.rawValue) }
        }
        let regions = Region.allCases.filter { settings.selectedRegions.contains($0.rawValue) }
        for industry in industries {
            for region in regions {
                currentStep = "Searching \(industry.shortName) in \(region.rawValue)..."
                do {
                    let found = try await pplxService.findCompanies(industry: industry, region: region, apiKey: settings.perplexityAPIKey)
                    let newOnes = found.filter { new in !companies.contains { $0.name.lowercased() == new.name.lowercased() } }
                    companies.append(contentsOf: newOnes)
                } catch { errorMessage = "Error \(industry.rawValue)/\(region.rawValue): \(error.localizedDescription)" }
            }
        }
        currentStep = "\(companies.count) companies found"; let selectedSizes = CompanySize.allCases.filter { settings.selectedCompanySizes.contains($0.rawValue) }; companies = companies.applySearchFilters(selectedSizes: selectedSizes, existingLeads: leads); currentStep = "\(companies.count) companies after filtering"; saveCompanies(); isLoading = false
    }

    // MARK: - 2) Kontakte finden - per-search + auto-add to Kontakte
    func findContacts(for company: Company) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key fehlt."; return }
        isLoading = true; currentStep = "Searching contacts at \(company.name)..."
        // Clear per-search results for this search
        currentSearchContacts = []
        do {
            let found = try await pplxService.findContacts(company: company, apiKey: settings.perplexityAPIKey)
            // Show in per-search results
            currentSearchContacts = found
            // Auto-add to main leads (Kontakte) - dedup
            let newLeads = found.filter { newLead in
                !leads.contains { $0.name.lowercased() == newLead.name.lowercased() && $0.company.lowercased() == newLead.company.lowercased() }
            }
            leads.append(contentsOf: newLeads)
            saveLeads()
            currentStep = "\(found.count) contacts found at \(company.name) (\(newLeads.count) new)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    func findContactsForAll() async {
        currentSearchContacts = []
        for company in companies { await findContacts(for: company) }
    }

    // MARK: - 3) Email verifizieren
    func verifyEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        isLoading = true; currentStep = "Verifying email for \(leads[idx].name)..."
        do {
            let result = try await pplxService.verifyEmail(lead: leads[idx], apiKey: settings.perplexityAPIKey)
            leads[idx].email = result.email; leads[idx].emailVerified = result.verified
            leads[idx].verificationNotes = result.notes
            leads[idx].status = result.verified ? .contacted : .identified
            saveLeads(); currentStep = result.verified ? "Email verified: \(result.email)" : "Not verified: \(result.notes)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    func verifyAllEmails() async {
        for lead in leads.filter({ !$0.emailVerified }) { await verifyEmail(for: lead.id) }
    }

    // MARK: - 4+5) Research + Email Draft
    func draftEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        guard leads[idx].emailVerified || leads[idx].isManuallyCreated else { errorMessage = "Email must be verified first."; return }
        isLoading = true; currentStep = "Researching challenges for \(leads[idx].company)..."
        do {
            let companyForResearch = companies.first { $0.name.lowercased() == leads[idx].company.lowercased() } ?? Company(name: leads[idx].company, industry: "", region: "")
            let challenges = try await pplxService.researchChallenges(company: companyForResearch, apiKey: settings.perplexityAPIKey)
            currentStep = "Creating personalized email for \(leads[idx].name)..."
            let email = try await pplxService.draftEmail(lead: leads[idx], challenges: challenges, senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].draftedEmail = email; leads[idx].status = .emailDrafted; saveLeads()
            currentStep = "Email draft created for \(leads[idx].name)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    func draftAllEmails() async {
        for lead in leads.filter({ $0.emailVerified && $0.draftedEmail == nil }) { await draftEmail(for: lead.id) }
    }

    func initializeSheet() async {
        guard !settings.spreadsheetID.isEmpty else { return }
        do { try await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID) }
        catch { errorMessage = "Sheet-Init: \(error.localizedDescription)" }
    }

    // MARK: - Lead Management
    func deleteLead(_ leadID: UUID) { leads.removeAll { $0.id == leadID }; saveLeads() }
    func updateLead(_ lead: Lead) { if let idx = leads.firstIndex(where: { $0.id == lead.id }) { leads[idx] = lead; saveLeads() } }

    // MARK: - Stats
    var statsIdentified: Int { leads.count }
    var statsVerified: Int { leads.filter { $0.emailVerified }.count }
    var statsSent: Int { leads.filter { $0.dateEmailSent != nil }.count }
    var statsReplied: Int { leads.filter { !$0.replyReceived.isEmpty }.count }
    var statsFollowUp: Int { leads.filter { $0.dateFollowUpSent != nil }.count }
    var statsSocialPostsTotal: Int { socialPosts.count }
    var statsSocialPostsLinkedIn: Int { socialPosts.filter { $0.platform == .linkedin }.count }
    var statsSocialPostsTwitter: Int { socialPosts.filter { $0.platform == .twitter }.count }
    var statsSocialPostsPublished: Int { socialPosts.filter { $0.isPublished }.count }
    var statsSocialPostsThisWeek: Int { let w = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(); return socialPosts.filter { $0.createdDate >= w }.count }
    var statsCompanies: Int { companies.count }
    var statsDraftsReady: Int { leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }.count }
    var statsApproved: Int { leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }.count }
    var statsConversionRate: Double { guard statsSent > 0 else { return 0 }; return Double(statsReplied) / Double(statsSent) * 100 }
    var statsFollowUpsPending: Int { leads.filter { $0.followUpEmail != nil && $0.dateFollowUpSent == nil }.count }
    var statsIndustryCounts: [(industry: String, count: Int)] {
        Dictionary(grouping: companies, by: { $0.industry }).map { (industry: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }
    // NEW: Unsubscribe count
    var statsUnsubscribed: Int {
        replies.filter { reply in
            let body = reply.body.lowercased()
            let subject = reply.subject.lowercased()
            return body.contains("unsubscribe") || body.contains("abmelden") || body.contains("austragen") || subject.contains("unsubscribe") || subject.contains("abmelden")
        }.count
    }

    // MARK: - Persistenz
    private func saveLeads() { if let data = try? JSONEncoder().encode(leads) { try? data.write(to: saveURL) } }
    private func loadLeads() { guard let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode([Lead].self, from: data) else { return }; leads = saved }
    private func saveCompanies() { if let data = try? JSONEncoder().encode(companies) { try? data.write(to: companiesSaveURL) } }
    private func loadCompanies() { guard let data = try? Data(contentsOf: companiesSaveURL), let saved = try? JSONDecoder().decode([Company].self, from: data) else { return }; companies = saved }

    // MARK: - 5) Email freigeben
    func approveEmail(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].draftedEmail?.isApproved = true; leads[idx].status = .emailApproved; saveLeads()
    }

    // MARK: - 6) Email senden
    func sendEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }), let email = leads[idx].draftedEmail, email.isApproved else { errorMessage = "Email must be approved first."; return }
        isLoading = true; currentStep = "Sending email to \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(to: leads[idx].email, from: Self.senderEmail, subject: email.subject, body: email.body)
            leads[idx].dateEmailSent = Date(); leads[idx].draftedEmail?.sentDate = Date(); leads[idx].status = .emailSent; saveLeads()
            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.logEmailEvent(spreadsheetID: settings.spreadsheetID, lead: leads[idx], emailType: "Initial", subject: email.subject, body: email.body, summary: "Outreach to \(leads[idx].name) (\(leads[idx].company))")
            }
            currentStep = "Email sent to \(leads[idx].email)"
        } catch { errorMessage = "Send failed: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - 7) Antworten pruefen - ALLE Antworten anzeigen, inkl. Unsubscribe
    func checkForReplies() async {
        var sentSubjects: [String] = []
        for lead in leads {
            if lead.dateEmailSent != nil, let subj = lead.draftedEmail?.subject, !subj.isEmpty { sentSubjects.append(subj) }
            if lead.dateFollowUpSent != nil, let subj = lead.followUpEmail?.subject, !subj.isEmpty { sentSubjects.append(subj) }
        }
        let uniqueSubjects = Array(Set(sentSubjects))
        let sentLeadEmails = leads.filter { $0.dateEmailSent != nil || $0.dateFollowUpSent != nil }.map { $0.email }
        guard !uniqueSubjects.isEmpty else { statusMessage = "No sent emails to check."; return }
        isLoading = true; currentStep = "Checking inbox for replies..."
        do {
            let found = try await gmailService.checkReplies(sentSubjects: uniqueSubjects, leadEmails: sentLeadEmails)
            // Store ALL replies (not just matched ones)
            replies = found
            for reply in found {
                let replyFrom = reply.from.lowercased()
                let replySubject = reply.subject.lowercased().replacingOccurrences(of: "re: ", with: "").replacingOccurrences(of: "aw: ", with: "").replacingOccurrences(of: "fwd: ", with: "").trimmingCharacters(in: .whitespaces)
                // Check if this is an unsubscribe
                let isUnsubscribe = reply.body.lowercased().contains("unsubscribe") || reply.body.lowercased().contains("abmelden") || reply.body.lowercased().contains("austragen") || reply.subject.lowercased().contains("unsubscribe")
                var matchedIdx: Int?
                matchedIdx = leads.firstIndex(where: { lead in
                    if let draftSubj = lead.draftedEmail?.subject, !draftSubj.isEmpty {
                        let cleanDraft = draftSubj.lowercased().replacingOccurrences(of: "re: ", with: "").replacingOccurrences(of: "aw: ", with: "").trimmingCharacters(in: .whitespaces)
                        if replySubject.contains(cleanDraft) || cleanDraft.contains(replySubject) { return true }
                        let draftWords = Set(cleanDraft.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        let replyWords = Set(replySubject.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        if !draftWords.isEmpty && Double(draftWords.intersection(replyWords).count) / Double(draftWords.count) > 0.5 { return true }
                    }
                    if let fuSubj = lead.followUpEmail?.subject, !fuSubj.isEmpty {
                        let cleanFU = fuSubj.lowercased().replacingOccurrences(of: "re: ", with: "").replacingOccurrences(of: "aw: ", with: "").trimmingCharacters(in: .whitespaces)
                        if replySubject.contains(cleanFU) || cleanFU.contains(replySubject) { return true }
                    }
                    return false
                })
                if matchedIdx == nil {
                    matchedIdx = leads.firstIndex(where: { lead in !lead.email.isEmpty && replyFrom.contains(lead.email.lowercased()) && (lead.dateEmailSent != nil || lead.dateFollowUpSent != nil) })
                }
                if let idx = matchedIdx {
                    leads[idx].replyReceived = reply.snippet
                    leads[idx].status = isUnsubscribe ? .doNotContact : .replied
                    if !settings.spreadsheetID.isEmpty {
                        try? await sheetsService.logReplyReceived(spreadsheetID: settings.spreadsheetID, lead: leads[idx], replySubject: reply.subject, replySnippet: reply.snippet, replyFrom: reply.from)
                    }
                }
            }
            saveLeads(); currentStep = "\(found.count) replies found"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - 8) Follow-Up
    func checkFollowUpsNeeded() -> [Lead] {
        let calendar = Calendar.current
        return leads.filter { lead in
            guard lead.status == .emailSent, let sentDate = lead.dateEmailSent, lead.replyReceived.isEmpty, lead.followUpEmail == nil else { return false }
            return (calendar.dateComponents([.day], from: sentDate, to: Date()).day ?? 0) >= 14
        }
    }

    func draftFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }), let originalEmail = leads[idx].draftedEmail else { return }
        isLoading = true; currentStep = "Creating follow-up for \(leads[idx].name)..."
        do {
            let followUp = try await pplxService.draftFollowUp(lead: leads[idx], originalEmail: originalEmail.body, followUpEmail: leads[idx].followUpEmail?.body ?? "", replyReceived: leads[idx].replyReceived, senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].followUpEmail = followUp; leads[idx].status = .followUpDrafted; saveLeads()
            currentStep = "Follow-up created for \(leads[idx].name)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    func approveFollowUp(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].followUpEmail?.isApproved = true; saveLeads()
    }

    func sendFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }), let followUp = leads[idx].followUpEmail, followUp.isApproved else { errorMessage = "Follow-up must be approved first."; return }
        isLoading = true; currentStep = "Sending follow-up to \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(to: leads[idx].email, from: Self.senderEmail, subject: followUp.subject, body: followUp.body)
            leads[idx].dateFollowUpSent = Date(); leads[idx].followUpEmail?.sentDate = Date(); leads[idx].status = .followUpSent; saveLeads()
            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.logEmailEvent(spreadsheetID: settings.spreadsheetID, lead: leads[idx], emailType: "Follow-Up", subject: followUp.subject, body: followUp.body, summary: "Follow-up to \(leads[idx].name) (\(leads[idx].company))")
            }
            currentStep = "Follow-up sent to \(leads[idx].email)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - Google Sheets
    func refreshSheetData() async {
        guard !settings.spreadsheetID.isEmpty else { errorMessage = "Spreadsheet ID missing."; return }
        isLoading = true
        do { sheetData = try await sheetsService.readAllLeads(spreadsheetID: settings.spreadsheetID); currentStep = "\(sheetData.count) rows loaded" }
        catch { errorMessage = "Sheet error: \(error.localizedDescription)" }
        isLoading = false
    }

    func cancelOperation() { currentTask?.cancel(); currentTask = nil; isLoading = false; currentStep = ""; statusMessage = "Operation cancelled" }

    // MARK: - Manual Entry
    func addCompanyManually(_ company: Company) {
        if !companies.contains(where: { $0.name.lowercased() == company.name.lowercased() }) { companies.append(company); statusMessage = "Company \(company.name) added" }
        else { errorMessage = "Company \(company.name) already exists" }
    }

    func addLeadManually(_ lead: Lead) {
        if !leads.contains(where: { $0.name.lowercased() == lead.name.lowercased() && $0.company.lowercased() == lead.company.lowercased() }) {
            leads.append(lead); saveLeads(); statusMessage = "Contact \(lead.name) added"
        } else { errorMessage = "Contact \(lead.name) at \(lead.company) already exists" }
    }

    func addTestCompany() {
        let testCompany = Company(name: "Harpocrates Corp", industry: "K - Finanzdienstleistungen", region: "DACH", website: "https://harpocrates-corp.com", description: "RegTech Startup")
        if !companies.contains(where: { $0.name == "Harpocrates Corp" }) { companies.append(testCompany); statusMessage = "Test company added" }
        let testLead = Lead(name: "Martin Foerster", title: "CEO & Founder", company: testCompany.name, email: "mf@harpocrates-corp.com", emailVerified: true, linkedInURL: "https://linkedin.com/in/martinfoerster", status: .contacted, source: "test", isManuallyCreated: true)
        if !leads.contains(where: { $0.email == "mf@harpocrates-corp.com" }) { leads.append(testLead); saveLeads(); statusMessage = "Test contact added" }
    }

    // MARK: - Draft Management
    func updateDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = OutboundEmail(id: lead.draftedEmail?.id ?? UUID(), subject: subject, body: body, isApproved: true)
            saveLeads(); statusMessage = "Draft for \(lead.name) updated"
        }
    }

    func deleteDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = nil; leads[index].status = .identified; saveLeads()
            statusMessage = "Draft for \(lead.name) deleted"
        }
    }

    func sendEmail(to lead: Lead) async {
        guard let draft = lead.draftedEmail else { errorMessage = "No draft for \(lead.name)"; return }
        guard !lead.email.isEmpty else { errorMessage = "No email for \(lead.name)"; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }
        isLoading = true; errorMessage = ""; currentStep = "Sending email to \(lead.name)..."
        do {
            _ = try await gmailService.sendEmail(to: lead.email, from: Self.senderEmail, subject: draft.subject, body: draft.body)
            if let index = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[index].status = .emailSent; leads[index].dateEmailSent = Date(); leads[index].draftedEmail?.sentDate = Date(); saveLeads()
                if !settings.spreadsheetID.isEmpty {
                    try? await sheetsService.logEmailEvent(spreadsheetID: settings.spreadsheetID, lead: leads[index], emailType: "Initial", subject: draft.subject, body: draft.body, summary: "Outreach to \(lead.name) (\(lead.company))")
                }
            }
            statusMessage = "Email to \(lead.name) sent"
        } catch { errorMessage = "Send failed: \(error.localizedDescription)" }
        isLoading = false; currentStep = ""
    }

    func emailSentCount(for lead: Lead) -> Int {
        var count = 0; if lead.dateEmailSent != nil { count += 1 }; if lead.dateFollowUpSent != nil { count += 1 }; return count
    }

    // MARK: - Follow-Up from Contact
    func draftFollowUpFromContact(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        let lead = leads[idx]
        guard lead.dateEmailSent != nil else { errorMessage = "Send an email first."; return }
        if lead.followUpEmail != nil { statusMessage = "Follow-up draft already exists for \(lead.name)."; return }
        guard let originalEmail = lead.draftedEmail else { errorMessage = "No original draft for \(lead.name)"; return }
        isLoading = true; currentStep = "Creating follow-up for \(lead.name)..."
        do {
            let followUp = try await pplxService.draftFollowUp(lead: lead, originalEmail: originalEmail.body, followUpEmail: lead.followUpEmail?.body ?? "", replyReceived: lead.replyReceived, senderName: settings.senderName, apiKey: settings.perplexityAPIKey)
            leads[idx].followUpEmail = followUp; leads[idx].status = .followUpDrafted; saveLeads()
            currentStep = "Follow-up created for \(leads[idx].name)"
        } catch { errorMessage = "Error: \(error.localizedDescription)" }
        isLoading = false
    }

    func quickDraftAndShowInOutbox(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        if leads[idx].draftedEmail == nil { await draftEmail(for: leadID) }
        if leads[idx].draftedEmail != nil && leads[idx].draftedEmail?.isApproved == false {
            leads[idx].draftedEmail?.isApproved = true; leads[idx].status = .emailApproved; saveLeads()
        }
    }

    // MARK: - Follow-Up Draft Management
    func updateFollowUpDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = OutboundEmail(id: lead.followUpEmail?.id ?? UUID(), subject: subject, body: body, isApproved: true)
            saveLeads(); statusMessage = "Follow-up draft for \(lead.name) updated"
        }
    }

    func deleteFollowUpDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = nil; leads[index].status = .emailSent; saveLeads()
            statusMessage = "Follow-up draft for \(lead.name) deleted"
        }
    }

    // MARK: - Purge
    func purgeAllExcept(companyName: String) {
        let keepName = companyName.lowercased()
        let bl = leads.count; let bc = companies.count
        leads = leads.filter { $0.company.lowercased().contains(keepName) }
        companies = companies.filter { $0.name.lowercased().contains(keepName) }
        saveLeads(); saveCompanies(); replies = []
        statusMessage = "Purged: \(bl - leads.count) leads and \(bc - companies.count) companies removed."
    }

    // MARK: - Social Post Generation
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform = .linkedin, industries: [String] = []) async {
        guard !settings.perplexityAPIKey.isEmpty else { errorMessage = "Perplexity API Key missing."; return }
        isLoading = true; currentStep = "Generating \(platform.rawValue) post..."
        do {
            var post = try await pplxService.generateSocialPost(topic: topic, platform: platform, industries: industries.isEmpty ? settings.selectedIndustries : industries, existingPosts: socialPosts, apiKey: settings.perplexityAPIKey)
            post.content = SocialPost.ensureFooter(post.content)
            socialPosts.insert(post, at: 0); saveSocialPosts(); currentStep = "Post created"
        } catch { errorMessage = "Post generation failed: \(error.localizedDescription)" }
        isLoading = false
    }

    func deleteSocialPost(_ postID: UUID) { socialPosts.removeAll { $0.id == postID }; saveSocialPosts() }

    func updateSocialPost(_ post: SocialPost) {
        if let idx = socialPosts.firstIndex(where: { $0.id == post.id }) {
            var fixedPost = post; fixedPost.content = SocialPost.ensureFooter(post.content)
            socialPosts[idx] = fixedPost; saveSocialPosts()
        }
    }

    func copyPostToClipboard(_ post: SocialPost) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SocialPost.ensureFooter(post.content), forType: .string)
        statusMessage = "Post copied to clipboard"
        #endif
    }

    private func saveSocialPosts() { if let data = try? JSONEncoder().encode(socialPosts) { try? data.write(to: socialPostsSaveURL) } }
    private func loadSocialPosts() { guard let data = try? Data(contentsOf: socialPostsSaveURL), let saved = try? JSONDecoder().decode([SocialPost].self, from: data) else { return }; socialPosts = saved }

    private func migrateSocialPostFooters() {
        var changed = false
        for i in socialPosts.indices {
            let fixed = SocialPost.ensureFooter(socialPosts[i].content)
            if fixed != socialPosts[i].content { socialPosts[i].content = fixed; changed = true }
        }
        if changed { saveSocialPosts() }
    }

    // MARK: - Email Pipeline
    func approveAllEmails() {
        var count = 0
        for i in leads.indices {
            if leads[i].draftedEmail != nil && leads[i].draftedEmail?.isApproved == false {
                leads[i].draftedEmail?.isApproved = true; leads[i].status = .emailApproved; count += 1
            }
        }
        saveLeads(); statusMessage = "\(count) emails approved"
    }

    func sendAllApproved() async {
        let approved = leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }
        guard !approved.isEmpty else { statusMessage = "No approved emails to send."; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }
        isLoading = true; var sentCount = 0; var failCount = 0
        for lead in approved {
            currentStep = "Sending \(sentCount + 1)/\(approved.count) to \(lead.name)..."
            do {
                guard let draft = lead.draftedEmail else { continue }
                _ = try await gmailService.sendEmail(to: lead.email, from: Self.senderEmail, subject: draft.subject, body: draft.body)
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].status = .emailSent; leads[idx].dateEmailSent = Date(); leads[idx].draftedEmail?.sentDate = Date(); saveLeads()
                    if !settings.spreadsheetID.isEmpty { try? await sheetsService.logEmailEvent(spreadsheetID: settings.spreadsheetID, lead: leads[idx], emailType: "Initial", subject: draft.subject, body: draft.body, summary: "Outreach to \(lead.name) (\(lead.company))") }
                }
                sentCount += 1; try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch { failCount += 1 }
        }
        isLoading = false; currentStep = ""
        statusMessage = "\(sentCount) emails sent" + (failCount > 0 ? ", \(failCount) failed" : "")
    }

    func sendAllFollowUps() async {
        let ready = leads.filter { $0.followUpEmail?.isApproved == true && $0.dateFollowUpSent == nil }
        guard !ready.isEmpty else { statusMessage = "No approved follow-ups to send."; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }
        isLoading = true; var sentCount = 0
        for lead in ready {
            currentStep = "Sending follow-up \(sentCount + 1)/\(ready.count) to \(lead.name)..."
            do {
                guard let followUp = lead.followUpEmail else { continue }
                _ = try await gmailService.sendEmail(to: lead.email, from: Self.senderEmail, subject: followUp.subject, body: followUp.body)
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].dateFollowUpSent = Date(); leads[idx].followUpEmail?.sentDate = Date(); leads[idx].status = .followUpSent; saveLeads()
                    if !settings.spreadsheetID.isEmpty { try? await sheetsService.logEmailEvent(spreadsheetID: settings.spreadsheetID, lead: leads[idx], emailType: "Follow-Up", subject: followUp.subject, body: followUp.body, summary: "Follow-up to \(lead.name) (\(lead.company))") }
                }
                sentCount += 1; try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch { }
        }
        isLoading = false; currentStep = ""; statusMessage = "\(sentCount) follow-ups sent"
    }
}
