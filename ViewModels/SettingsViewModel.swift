import Foundation
import Combine
import SwiftUI

// MARK: - SettingsViewModel
// Manages all app settings UI state: API keys, email config, send windows,
// Google integration, and data management. Bridges ConfigurableSettings and DataStore.

@MainActor
class SettingsViewModel: ObservableObject {

  // MARK: - API Keys
  @Published var perplexityAPIKey: String = ""
  @Published var isPerplexityKeyValid: Bool = false

  // MARK: - Email Settings
  @Published var senderName: String = ""
  @Published var senderEmail: String = ""
  @Published var emailSignature: String = ""
  @Published var maxEmailsPerDay: Int = 50
  @Published var minPauseBetweenEmails: Double = 30
  @Published var maxPauseBetweenEmails: Double = 120

  // MARK: - Send Window
  @Published var sendWindowStart: Int = 8
  @Published var sendWindowEnd: Int = 18
  @Published var sendOnWeekends: Bool = false

  // MARK: - Follow-Up
  @Published var followUpDelayDays: Int = 3
  @Published var maxFollowUps: Int = 3
  @Published var autoFollowUp: Bool = false

  // MARK: - Google Integration
  @Published var isGoogleConnected: Bool = false
  @Published var googleEmail: String = ""
  @Published var sheetsSpreadsheetID: String = ""

  // MARK: - Prospecting
  @Published var defaultIndustry: String = ""
  @Published var defaultRegion: String = ""
  @Published var minCompanySize: Int = 200
  @Published var targetRoles: [String] = ["CCO", "Head of Compliance", "DPO"]

  // MARK: - UI State
  @Published var isSaving = false
  @Published var showingSaveConfirmation = false
  @Published var lastError: String?
  @Published var selectedTab: SettingsTab = .general

  private var cancellables = Set<AnyCancellable>()

  // MARK: - Init

  init() {
    loadSettings()
  }

  // MARK: - Load Settings

  func loadSettings() {
    let settings = DataStore.shared.settings
    perplexityAPIKey = settings.perplexityAPIKey
    senderName = settings.senderName
    senderEmail = settings.senderEmail
    emailSignature = settings.emailSignature
    maxEmailsPerDay = settings.maxEmailsPerDay
    minPauseBetweenEmails = settings.minPauseBetweenEmails
    maxPauseBetweenEmails = settings.maxPauseBetweenEmails
    sendWindowStart = settings.sendWindowStart
    sendWindowEnd = settings.sendWindowEnd
    sendOnWeekends = settings.sendOnWeekends
    followUpDelayDays = settings.followUpDelayDays
    maxFollowUps = settings.maxFollowUps
    autoFollowUp = settings.autoFollowUp
    sheetsSpreadsheetID = settings.sheetsSpreadsheetID
    defaultIndustry = settings.defaultIndustry
    defaultRegion = settings.defaultRegion
    minCompanySize = settings.minCompanySize
    isPerplexityKeyValid = !perplexityAPIKey.isEmpty
  }

  // MARK: - Save Settings

  func saveSettings() {
    isSaving = true
    var settings = DataStore.shared.settings
    settings.perplexityAPIKey = perplexityAPIKey
    settings.senderName = senderName
    settings.senderEmail = senderEmail
    settings.emailSignature = emailSignature
    settings.maxEmailsPerDay = maxEmailsPerDay
    settings.minPauseBetweenEmails = minPauseBetweenEmails
    settings.maxPauseBetweenEmails = maxPauseBetweenEmails
    settings.sendWindowStart = sendWindowStart
    settings.sendWindowEnd = sendWindowEnd
    settings.sendOnWeekends = sendOnWeekends
    settings.followUpDelayDays = followUpDelayDays
    settings.maxFollowUps = maxFollowUps
    settings.autoFollowUp = autoFollowUp
    settings.sheetsSpreadsheetID = sheetsSpreadsheetID
    settings.defaultIndustry = defaultIndustry
    settings.defaultRegion = defaultRegion
    settings.minCompanySize = minCompanySize
    DataStore.shared.settings = settings
    DataStore.shared.saveSettings()
    isPerplexityKeyValid = !perplexityAPIKey.isEmpty
    isSaving = false
    showingSaveConfirmation = true

    // Auto-dismiss confirmation
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.showingSaveConfirmation = false
    }
  }

  // MARK: - Validation

  var isEmailConfigValid: Bool {
    !senderName.isEmpty && !senderEmail.isEmpty && senderEmail.contains("@")
  }

  var isSendWindowValid: Bool {
    sendWindowStart < sendWindowEnd && sendWindowStart >= 0 && sendWindowEnd <= 23
  }

  var canSave: Bool {
    isEmailConfigValid && isSendWindowValid
  }

  // MARK: - Google Integration

  func connectGoogle() async {
    // Triggers Google OAuth flow
    // Integration with GoogleAuthService
  }

  func disconnectGoogle() {
    isGoogleConnected = false
    googleEmail = ""
  }

  // MARK: - Data Management

  func exportAllData() -> String {
    // Delegate to DataStore for full data export
    return "Export initiated"
  }

  func resetToDefaults() {
    senderName = ""
    senderEmail = ""
    emailSignature = ""
    maxEmailsPerDay = 50
    minPauseBetweenEmails = 30
    maxPauseBetweenEmails = 120
    sendWindowStart = 8
    sendWindowEnd = 18
    sendOnWeekends = false
    followUpDelayDays = 3
    maxFollowUps = 3
    autoFollowUp = false
    defaultIndustry = ""
    defaultRegion = ""
    minCompanySize = 200
  }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
  case general = "General"
  case email = "Email"
  case prospecting = "Prospecting"
  case integrations = "Integrations"
  case data = "Data Management"
}
