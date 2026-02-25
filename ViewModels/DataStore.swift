import Foundation
import Combine
import SwiftUI

// MARK: - DataStore
// Zentrale Datenschicht fuer alle shared state
// Ersetzt die verstreute Persistenz in AppViewModel
@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    // MARK: - Published State
    @Published var leads: [Lead] = []
    @Published var companies: [Company] = []
    @Published var socialPosts: [SocialPost] = []
    @Published var replies: [GmailService.GmailMessage] = []
    @Published var sheetData: [[String]] = []
    @Published var settings = AppSettings()

    // MARK: - Blocklist (Aufgabe 9: Opt-Out)
    @Published var blockedEmails: Set<String> = []
    @Published var blockedDomains: Set<String> = []

    // MARK: - Scheduling Queue (Aufgabe 5)
    @Published var scheduledEmails: [ScheduledEmail] = []

    // MARK: - File URLs
    private let appDir: URL
    private let leadsURL: URL
    private let companiesURL: URL
    private let socialPostsURL: URL
    private let blocklistURL: URL
    private let scheduledURL: URL
    private let contactedDomainsURL: URL

    // MARK: - Contacted Domains (Aufgabe 6: Duplikat)
    @Published var contactedDomains: Set<String> = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        leadsURL = appDir.appendingPathComponent("leads.json")
        companiesURL = appDir.appendingPathComponent("companies.json")
        socialPostsURL = appDir.appendingPathComponent("socialPosts.json")
        blocklistURL = appDir.appendingPathComponent("blocklist.json")
        scheduledURL = appDir.appendingPathComponent("scheduled.json")
        contactedDomainsURL = appDir.appendingPathComponent("contactedDomains.json")
        loadAll()
    }

    // MARK: - Load All
    func loadAll() {
        loadSettings()
        loadLeads()
        loadCompanies()
        loadSocialPosts()
        loadBlocklist()
        loadScheduled()
        loadContactedDomains()
    }

    // MARK: - Settings
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "harpo_settings"),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "harpo_settings")
        }
    }

    // MARK: - Leads
    func saveLeads() {
        if let data = try? JSONEncoder().encode(leads) {
            try? data.write(to: leadsURL, options: .atomic)
        }
    }

    private func loadLeads() {
        guard let data = try? Data(contentsOf: leadsURL),
              let saved = try? JSONDecoder().decode([Lead].self, from: data) else { return }
        leads = saved
    }

    // MARK: - Companies
    func saveCompanies() {
        if let data = try? JSONEncoder().encode(companies) {
            try? data.write(to: companiesURL, options: .atomic)
        }
    }

    private func loadCompanies() {
        guard let data = try? Data(contentsOf: companiesURL),
              let saved = try? JSONDecoder().decode([Company].self, from: data) else { return }
        companies = saved
    }

    // MARK: - Social Posts
    func saveSocialPosts() {
        if let data = try? JSONEncoder().encode(socialPosts) {
            try? data.write(to: socialPostsURL, options: .atomic)
        }
    }

    private func loadSocialPosts() {
        guard let data = try? Data(contentsOf: socialPostsURL),
              let saved = try? JSONDecoder().decode([SocialPost].self, from: data) else { return }
        socialPosts = saved
    }

    // MARK: - Blocklist (Aufgabe 9)
    func saveBlocklist() {
        let dict: [String: [String]] = [
            "emails": Array(blockedEmails),
            "domains": Array(blockedDomains)
        ]
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: blocklistURL, options: .atomic)
        }
    }

    private func loadBlocklist() {
        guard let data = try? Data(contentsOf: blocklistURL),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        blockedEmails = Set(dict["emails"] ?? [])
        blockedDomains = Set(dict["domains"] ?? [])
    }

    func addToBlocklist(email: String) {
        blockedEmails.insert(email.lowercased())
        if let domain = email.split(separator: "@").last {
            blockedDomains.insert(String(domain).lowercased())
        }
        saveBlocklist()
    }

    func isBlocked(email: String) -> Bool {
        let lower = email.lowercased()
        if blockedEmails.contains(lower) { return true }
        if let domain = lower.split(separator: "@").last {
            if blockedDomains.contains(String(domain)) { return true }
        }
        return false
    }

    // MARK: - Scheduled Emails (Aufgabe 5)
    func saveScheduled() {
        if let data = try? JSONEncoder().encode(scheduledEmails) {
            try? data.write(to: scheduledURL, options: .atomic)
        }
    }

    private func loadScheduled() {
        guard let data = try? Data(contentsOf: scheduledURL),
              let saved = try? JSONDecoder().decode([ScheduledEmail].self, from: data) else { return }
        scheduledEmails = saved
    }

    // MARK: - Contacted Domains (Aufgabe 6)
    func addContactedDomain(_ domain: String) {
        contactedDomains.insert(domain.lowercased())
        saveContactedDomains()
    }

    func saveContactedDomains() {
        if let data = try? JSONEncoder().encode(Array(contactedDomains)) {
            try? data.write(to: contactedDomainsURL, options: .atomic)
        }
    }

    private func loadContactedDomains() {
        guard let data = try? Data(contentsOf: contactedDomainsURL),
              let saved = try? JSONDecoder().decode([String].self, from: data) else { return }
        contactedDomains = Set(saved)
    }

    // MARK: - Stats (moved from AppViewModel)
    var statsIdentified: Int { leads.count }
    var statsVerified: Int { leads.filter { $0.emailVerified }.count }
    var statsSent: Int { leads.filter { $0.dateEmailSent != nil }.count }
    var statsReplied: Int { leads.filter { !$0.replyReceived.isEmpty }.count }
    var statsFollowUp: Int { leads.filter { $0.dateFollowUpSent != nil }.count }
    var statsCompanies: Int { companies.count }
    var statsDraftsReady: Int { leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }.count }
    var statsApproved: Int { leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }.count }
    var statsConversionRate: Double {
        guard statsSent > 0 else { return 0 }
        return Double(statsReplied) / Double(statsSent) * 100
    }
}

// MARK: - ScheduledEmail Model (Aufgabe 5)
struct ScheduledEmail: Identifiable, Codable {
    let id: UUID
    var leadID: UUID
    var emailType: String // "initial" or "followup"
    var scheduledDate: Date
    var sent: Bool

    init(id: UUID = UUID(), leadID: UUID, emailType: String = "initial",
         scheduledDate: Date, sent: Bool = false) {
        self.id = id
        self.leadID = leadID
        self.emailType = emailType
        self.scheduledDate = scheduledDate
        self.sent = sent
    }
}
