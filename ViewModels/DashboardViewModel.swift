import Foundation
import Combine
import SwiftUI

// MARK: - DashboardViewModel
// Aggregates metrics from all services into a single dashboard view:
// pipeline stats, lead funnel, email performance, recent activity, and health.

@MainActor
class DashboardViewModel: ObservableObject {

  // MARK: - Pipeline Metrics
  @Published var totalCompanies: Int = 0
  @Published var totalLeads: Int = 0
  @Published var emailsSentToday: Int = 0
  @Published var emailsSentThisWeek: Int = 0
  @Published var emailsPending: Int = 0
  @Published var emailsApproved: Int = 0

  // MARK: - Lead Funnel
  @Published var leadsIdentified: Int = 0
  @Published var leadsContacted: Int = 0
  @Published var leadsResponded: Int = 0
  @Published var leadsConverted: Int = 0
  @Published var conversionRate: Double = 0.0

  // MARK: - Email Performance
  @Published var openRate: Double = 0.0
  @Published var replyRate: Double = 0.0
  @Published var bounceRate: Double = 0.0
  @Published var avgResponseTime: TimeInterval = 0

  // MARK: - Social
  @Published var socialPostsPublished: Int = 0
  @Published var socialPostsDraft: Int = 0

  // MARK: - Recent Activity
  @Published var recentActivities: [DashboardActivity] = []

  // MARK: - Health
  @Published var apiKeyConfigured: Bool = false
  @Published var googleConnected: Bool = false
  @Published var hasRecentErrors: Bool = false
  @Published var schedulerRunning: Bool = false

  // MARK: - UI State
  @Published var isRefreshing: Bool = false
  @Published var lastRefreshed: Date?
  @Published var selectedTimeRange: TimeRange = .week

  private var cancellables = Set<AnyCancellable>()
  private var refreshTimer: Timer?

  // MARK: - Init

  init() {
    refresh()
  }

  // MARK: - Refresh

  func refresh() {
    isRefreshing = true
    refreshPipelineMetrics()
    refreshLeadFunnel()
    refreshEmailPerformance()
    refreshRecentActivity()
    refreshHealth()
    lastRefreshed = Date()
    isRefreshing = false
  }

  // MARK: - Pipeline Metrics

  private func refreshPipelineMetrics() {
    let store = DataStore.shared
    totalCompanies = store.companies.count
    totalLeads = store.leads.count
    emailsSentToday = store.emailsSentToday
    emailsSentThisWeek = store.emailsSentThisWeek
    emailsPending = store.pendingEmails.count
    emailsApproved = store.approvedEmails.count
  }

  // MARK: - Lead Funnel

  private func refreshLeadFunnel() {
    let leads = DataStore.shared.leads
    leadsIdentified = leads.filter { $0.status == .identified }.count
    leadsContacted = leads.filter { $0.status == .contacted }.count
    leadsResponded = leads.filter { $0.status == .responded }.count
    leadsConverted = leads.filter { $0.status == .converted }.count

    let contacted = leadsContacted + leadsResponded + leadsConverted
    conversionRate = contacted > 0 ? Double(leadsConverted) / Double(contacted) * 100 : 0
  }

  // MARK: - Email Performance

  private func refreshEmailPerformance() {
    let analytics = AnalyticsService.shared
    openRate = analytics.openRate
    replyRate = analytics.replyRate
    bounceRate = analytics.bounceRate
    avgResponseTime = analytics.averageResponseTime
  }

  // MARK: - Recent Activity

  private func refreshRecentActivity() {
    var activities: [DashboardActivity] = []

    // Recent emails sent
    let recentEmails = DataStore.shared.recentlySentEmails.prefix(5)
    for email in recentEmails {
      activities.append(DashboardActivity(
        type: .emailSent,
        title: "Email sent to \(email.recipientName)",
        subtitle: email.subject,
        timestamp: email.sentAt ?? Date()
      ))
    }

    // Recent companies found
    let recentCompanies = DataStore.shared.recentlyAddedCompanies.prefix(3)
    for company in recentCompanies {
      activities.append(DashboardActivity(
        type: .companyFound,
        title: "Found: \(company.name)",
        subtitle: company.industry,
        timestamp: company.addedAt ?? Date()
      ))
    }

    // Sort by timestamp, newest first
    recentActivities = activities.sorted { $0.timestamp > $1.timestamp }
  }

  // MARK: - Health

  private func refreshHealth() {
    let settings = DataStore.shared.settings
    apiKeyConfigured = !settings.perplexityAPIKey.isEmpty
    googleConnected = !settings.sheetsSpreadsheetID.isEmpty
    hasRecentErrors = ErrorHandlingService.shared.hasRecentErrors
    schedulerRunning = SchedulerService.shared.isRunning
  }

  // MARK: - Auto Refresh

  func startAutoRefresh(interval: TimeInterval = 60) {
    refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  func stopAutoRefresh() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  // MARK: - Computed

  var healthScore: Int {
    var score = 0
    if apiKeyConfigured { score += 25 }
    if googleConnected { score += 25 }
    if !hasRecentErrors { score += 25 }
    if totalLeads > 0 { score += 25 }
    return score
  }

  var healthStatus: String {
    switch healthScore {
    case 100: return "Excellent"
    case 75...99: return "Good"
    case 50...74: return "Fair"
    default: return "Needs Attention"
    }
  }

  var emailQuotaUsed: Double {
    let max = Double(DataStore.shared.settings.maxEmailsPerDay)
    guard max > 0 else { return 0 }
    return Double(emailsSentToday) / max * 100
  }
}

// MARK: - Supporting Types

struct DashboardActivity: Identifiable {
  let id = UUID()
  let type: ActivityType
  let title: String
  let subtitle: String
  let timestamp: Date
}

enum ActivityType {
  case emailSent
  case emailReceived
  case companyFound
  case leadIdentified
  case socialPosted
  case error
}

enum TimeRange: String, CaseIterable {
  case today = "Today"
  case week = "This Week"
  case month = "This Month"
  case quarter = "This Quarter"
  case all = "All Time"
}
