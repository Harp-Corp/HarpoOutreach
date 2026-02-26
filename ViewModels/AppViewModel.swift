import Foundation
import Combine
import SwiftUI

// MARK: - AppViewModel (Main Coordinator)
// All business logic is split into extensions:
//   AppViewModel+Prospecting.swift   - company/contact finding, verification
//   AppViewModel+EmailPipeline.swift - drafting, approval, sending
//   AppViewModel+Inbox.swift         - replies, follow-ups
//   AppViewModel+Social.swift        - social post generation
//   AppViewModel+CSV.swift           - import/export

@MainActor
class AppViewModel: ObservableObject {

    // MARK: - Services
    let authService = GoogleAuthService()
    private var authCancellable: AnyCancellable?
    let pplxService = PerplexityService()
    lazy var gmailService = GmailService(authService: authService)
    lazy var sheetsService = GoogleSheetsService(authService: authService)

    // MARK: - Published State
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

    // Industry / region filter for Prospecting search
    @Published var selectedIndustryFilter: Industry?
    @Published var selectedRegionFilter: Region?

    // Per-search contact results (only current search)
    @Published var currentSearchContacts: [Lead] = []

    // Cancellable task handle
    var currentTask: Task<Void, Never>?

    // MARK: - Computed: sender email (task 10 - configurable)
    var senderEmail: String { settings.senderEmail }

    // MARK: - Legacy JSON URLs (used only for migration)
    private var legacyLeadsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HarpoOutreach/leads.json")
    }
    private var legacyCompaniesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HarpoOutreach/companies.json")
    }
    private var legacySocialPostsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HarpoOutreach/socialPosts.json")
    }

    // MARK: - Init
    init() {
        // Ensure app support directory exists
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        loadSettings()

        // MARK: Migration: JSON to SQLite
        migrateFromJSONIfNeeded()

        // Load from SQLite (DatabaseService)
        leads = DatabaseService.shared.loadLeads()
        companies = DatabaseService.shared.loadCompanies()

        // Social posts: check for legacy JSON first, then use in-memory array
        loadSocialPostsFromLegacy()
        migrateSocialPostFooters()

        configureAuth()

        // Auto-initialize Google Sheet on launch
        if !settings.spreadsheetID.isEmpty {
            Task { try? await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID) }
        }

        authCancellable = authService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Migration: JSON to SQLite
    private func migrateFromJSONIfNeeded() {
        let fm = FileManager.default
        var migratedLeads: [Lead] = []
        var migratedCompanies: [Company] = []

        // Migrate leads.json
        if fm.fileExists(atPath: legacyLeadsURL.path),
           let data = try? Data(contentsOf: legacyLeadsURL),
           let saved = try? JSONDecoder().decode([Lead].self, from: data) {
            migratedLeads = saved
        }

        // Migrate companies.json
        if fm.fileExists(atPath: legacyCompaniesURL.path),
           let data = try? Data(contentsOf: legacyCompaniesURL),
           let saved = try? JSONDecoder().decode([Company].self, from: data) {
            migratedCompanies = saved
        }

        if !migratedLeads.isEmpty || !migratedCompanies.isEmpty {
            // Load social posts from legacy JSON for migration too
            var migratedSocialPosts: [SocialPost] = []
            if let data = try? Data(contentsOf: legacySocialPostsURL),
               let saved = try? JSONDecoder().decode([SocialPost].self, from: data) {
                migratedSocialPosts = saved
            }
            DatabaseService.shared.migrateFromJSON(
                leads: migratedLeads,
                companies: migratedCompanies,
                socialPosts: migratedSocialPosts
            )
            // Remove old JSON files after successful migration
            try? fm.removeItem(at: legacyLeadsURL)
            try? fm.removeItem(at: legacyCompaniesURL)
        }
    }

    // MARK: - Auth Configuration
    private func configureAuth() {
        authService.configure(clientID: settings.googleClientID, clientSecret: settings.googleClientSecret)
    }

    // MARK: - Settings
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "harpo_settings")
        }
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
        let validClientSuffix = "etabo2nhj89ghcdphk2qj7fm9j3r5i5p"
        if settings.googleClientID.isEmpty || !settings.googleClientID.contains(validClientSuffix) {
            settings.googleClientID = defaults.googleClientID
            settings.googleClientSecret = defaults.googleClientSecret
            saveSettings()
        }
        let validPplxKeyPrefix = "N9JG4Kmy5Wk125V"
        if settings.perplexityAPIKey.isEmpty || !settings.perplexityAPIKey.contains(validPplxKeyPrefix) {
            settings.perplexityAPIKey = defaults.perplexityAPIKey
            saveSettings()
        }
    }

    // MARK: - Persistence (via DatabaseService)

    func saveLeads() {
        DatabaseService.shared.saveLeads(leads)
    }

    func saveCompanies() {
        DatabaseService.shared.saveCompanies(companies)
    }

    // Social posts still use in-memory + JSON (no DB schema for them)
    func saveSocialPosts() {
        if let data = try? JSONEncoder().encode(socialPosts) {
            try? data.write(to: legacySocialPostsURL)
        }
    }

    private func loadSocialPostsFromLegacy() {
        guard let data = try? Data(contentsOf: legacySocialPostsURL),
              let saved = try? JSONDecoder().decode([SocialPost].self, from: data) else { return }
        socialPosts = saved
    }

    func migrateSocialPostFooters() {
        var changed = false
        for i in socialPosts.indices {
            let fixed = SocialPost.ensureFooter(socialPosts[i].content)
            if fixed != socialPosts[i].content { socialPosts[i].content = fixed; changed = true }
        }
        if changed { saveSocialPosts() }
    }

    // MARK: - Lead Management
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

    // MARK: - Purge
    func purgeAllExcept(companyName: String) {
        let keepName = companyName.lowercased()
        let bl = leads.count; let bc = companies.count
        leads = leads.filter { $0.company.lowercased().contains(keepName) }
        companies = companies.filter { $0.name.lowercased().contains(keepName) }
        saveLeads()
        saveCompanies()
        replies = []
        statusMessage = "Purged: \(bl - leads.count) leads and \(bc - companies.count) companies removed."
    }

    // MARK: - Google Sheets
    func initializeSheet() async {
        guard !settings.spreadsheetID.isEmpty else { return }
        do { try await sheetsService.initializeSheet(spreadsheetID: settings.spreadsheetID) }
        catch { errorMessage = "Sheet-Init: \(error.localizedDescription)" }
    }

    func refreshSheetData() async {
        guard !settings.spreadsheetID.isEmpty else { errorMessage = "Spreadsheet ID missing."; return }
        isLoading = true
        do {
            sheetData = try await sheetsService.readAllLeads(spreadsheetID: settings.spreadsheetID)
            currentStep = "\(sheetData.count) rows loaded"
        } catch { errorMessage = "Sheet error: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - Misc
    func cancelOperation() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        currentStep = ""
        statusMessage = "Operation cancelled"
    }

    func emailSentCount(for lead: Lead) -> Int {
        var count = 0
        if lead.dateEmailSent != nil { count += 1 }
        if lead.dateFollowUpSent != nil { count += 1 }
        return count
    }

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
    var statsSocialPostsThisWeek: Int {
        let w = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return socialPosts.filter { $0.createdDate >= w }.count
    }
    var statsCompanies: Int { companies.count }
    var statsDraftsReady: Int { leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }.count }
    var statsApproved: Int { leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }.count }
    var statsConversionRate: Double {
        guard statsSent > 0 else { return 0 }
        return Double(statsReplied) / Double(statsSent) * 100
    }
    var statsFollowUpsPending: Int { leads.filter { $0.followUpEmail != nil && $0.dateFollowUpSent == nil }.count }
    var statsIndustryCounts: [(industry: String, count: Int)] {
        Dictionary(grouping: companies, by: { $0.industry })
            .map { (industry: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    var statsUnsubscribed: Int {
        replies.filter { reply in
            let body = reply.body.lowercased()
            let subject = reply.subject.lowercased()
            return body.contains("unsubscribe") || body.contains("abmelden")
                || body.contains("austragen") || subject.contains("unsubscribe")
                || subject.contains("abmelden")
        }.count
    }
    var statsOptedOut: Int { leads.filter { $0.optedOut }.count }
    var statsBlocked: Int { DatabaseService.shared.loadBlocklist().count }
}
