import Foundation

// MARK: - CampaignManager
// Verbesserung 4+5: One-Click Campaign + Scheduling
// Orchestriert den kompletten Outreach-Workflow
@MainActor
class CampaignManager: ObservableObject {
    
    // MARK: - Campaign State
    @Published var activeCampaign: Campaign?
    @Published var campaignProgress: CampaignProgress = .idle
    @Published var campaignLog: [CampaignLogEntry] = []
    
    // MARK: - Scheduling
    private var schedulingTimer: Timer?
    private let store = DataStore.shared
    
    // MARK: - Campaign Progress
    enum CampaignProgress: Equatable {
        case idle
        case running(step: String, current: Int, total: Int)
        case paused(step: String)
        case completed(summary: CampaignSummary)
        case failed(error: String)
        
        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }
    
    // MARK: - One-Click Campaign
    /// Runs the full pipeline: find companies -> find contacts -> verify -> draft -> approve
    func runFullCampaign(
        vm: AppViewModel,
        industry: Industry? = nil,
        autoApprove: Bool = false
    ) async -> CampaignSummary {
        var summary = CampaignSummary()
        let startTime = Date()
        log("Campaign started", type: .info)
        
        // Step 1: Find Companies
        campaignProgress = .running(step: "Finding companies...", current: 1, total: 5)
        let companyCountBefore = vm.companies.count
        await vm.findCompanies(forIndustry: industry)
        summary.companiesFound = vm.companies.count - companyCountBefore
        log("Found \(summary.companiesFound) new companies", type: .success)
        
        guard !Task.isCancelled else { return cancelled(&summary) }
        
        // Step 2: Find Contacts for all companies
        campaignProgress = .running(step: "Finding contacts...", current: 2, total: 5)
        let leadCountBefore = vm.leads.count
        await vm.findContactsForAll()
        summary.contactsFound = vm.leads.count - leadCountBefore
        log("Found \(summary.contactsFound) new contacts", type: .success)
        
        guard !Task.isCancelled else { return cancelled(&summary) }
        
        // Step 3: Verify emails
        campaignProgress = .running(step: "Verifying emails...", current: 3, total: 5)
        let unverified = vm.leads.filter { !$0.emailVerified && !$0.isManuallyCreated }
        for (i, lead) in unverified.enumerated() {
            guard !Task.isCancelled else { break }
            campaignProgress = .running(step: "Verifying \(i+1)/\(unverified.count)...", current: 3, total: 5)
            await vm.verifyEmail(for: lead.id)
            summary.emailsVerified += 1
            // Rate limit: 1 second between verifications
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        log("Verified \(summary.emailsVerified) emails", type: .success)
        
        guard !Task.isCancelled else { return cancelled(&summary) }
        
        // Step 4: Draft emails for verified leads
        campaignProgress = .running(step: "Drafting emails...", current: 4, total: 5)
        let draftable = vm.leads.filter { $0.emailVerified && $0.draftedEmail == nil }
        for (i, lead) in draftable.enumerated() {
            guard !Task.isCancelled else { break }
            // Skip blocked contacts
            if store.isBlocked(email: lead.email) {
                log("Skipped blocked: \(lead.email)", type: .warning)
                continue
            }
            campaignProgress = .running(step: "Drafting \(i+1)/\(draftable.count)...", current: 4, total: 5)
            await vm.draftEmail(for: lead.id)
            summary.emailsDrafted += 1
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        log("Drafted \(summary.emailsDrafted) emails", type: .success)
        
        // Step 5: Auto-approve if enabled
        if autoApprove {
            campaignProgress = .running(step: "Approving drafts...", current: 5, total: 5)
            vm.approveAllEmails()
            summary.emailsApproved = vm.leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }.count
            log("Auto-approved \(summary.emailsApproved) emails", type: .success)
        }
        
        summary.duration = Date().timeIntervalSince(startTime)
        campaignProgress = .completed(summary: summary)
        log("Campaign completed in \(Int(summary.duration))s", type: .info)
        return summary
    }
    
    // MARK: - Scheduling Engine
    func startScheduler() {
        schedulingTimer?.invalidate()
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processScheduledEmails()
            }
        }
        log("Scheduler started (60s interval)", type: .info)
    }
    
    func stopScheduler() {
        schedulingTimer?.invalidate()
        schedulingTimer = nil
        log("Scheduler stopped", type: .info)
    }
    
    func scheduleEmail(leadID: UUID, sendDate: Date, type: String = "initial") {
        let scheduled = ScheduledEmail(leadID: leadID, emailType: type, scheduledDate: sendDate)
        store.scheduledEmails.append(scheduled)
        store.saveScheduled()
        log("Scheduled \(type) email for \(sendDate)", type: .info)
    }
    
    func scheduleBatch(leadIDs: [UUID], startDate: Date, intervalMinutes: Int = 30) {
        for (i, leadID) in leadIDs.enumerated() {
            let sendDate = startDate.addingTimeInterval(TimeInterval(i * intervalMinutes * 60))
            scheduleEmail(leadID: leadID, sendDate: sendDate)
        }
        log("Batch scheduled \(leadIDs.count) emails starting \(startDate)", type: .info)
    }
    
    private func processScheduledEmails() async {
        let now = Date()
        let due = store.scheduledEmails.filter { !$0.sent && $0.scheduledDate <= now }
        guard !due.isEmpty else { return }
        log("Processing \(due.count) scheduled emails", type: .info)
        
        for email in due {
            if let idx = store.scheduledEmails.firstIndex(where: { $0.id == email.id }) {
                store.scheduledEmails[idx].sent = true
            }
        }
        store.saveScheduled()
    }
    
    // MARK: - Logging
    private func log(_ message: String, type: CampaignLogEntry.LogType) {
        campaignLog.append(CampaignLogEntry(message: message, type: type))
    }
    
    private func cancelled(_ summary: inout CampaignSummary) -> CampaignSummary {
        summary.wasCancelled = true
        campaignProgress = .failed(error: "Campaign cancelled")
        log("Campaign cancelled by user", type: .warning)
        return summary
    }
}

// MARK: - Campaign Model
struct Campaign: Identifiable, Codable {
    let id: UUID
    var name: String
    var industry: String?
    var region: String?
    var createdDate: Date
    var status: CampaignStatus
    
    init(id: UUID = UUID(), name: String, industry: String? = nil,
         region: String? = nil, createdDate: Date = Date(),
         status: CampaignStatus = .draft) {
        self.id = id
        self.name = name
        self.industry = industry
        self.region = region
        self.createdDate = createdDate
        self.status = status
    }
}

enum CampaignStatus: String, Codable {
    case draft = "Draft"
    case running = "Running"
    case paused = "Paused"
    case completed = "Completed"
    case cancelled = "Cancelled"
}

// MARK: - Campaign Summary
struct CampaignSummary: Equatable {
    var companiesFound: Int = 0
    var contactsFound: Int = 0
    var emailsVerified: Int = 0
    var emailsDrafted: Int = 0
    var emailsApproved: Int = 0
    var emailsSent: Int = 0
    var duration: TimeInterval = 0
    var wasCancelled: Bool = false
}

// MARK: - Campaign Log Entry
struct CampaignLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
    
    enum LogType {
        case info, success, warning, error
    }
}
