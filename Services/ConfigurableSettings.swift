//
//  ConfigurableSettings.swift
//  HarpoOutreach
//
//  Centralized, configurable app settings replacing hardcoded values
//

import Foundation
import Combine

// MARK: - App Settings

class AppSettings: ObservableObject {
  static let shared = AppSettings()
  
  private let defaults = UserDefaults.standard
  
  // MARK: - Email Settings
  
  @Published var senderEmail: String {
    didSet { defaults.set(senderEmail, forKey: Keys.senderEmail) }
  }
  
  @Published var senderName: String {
    didSet { defaults.set(senderName, forKey: Keys.senderName) }
  }
  
  @Published var companyName: String {
    didSet { defaults.set(companyName, forKey: Keys.companyName) }
  }
  
  @Published var emailSignature: String {
    didSet { defaults.set(emailSignature, forKey: Keys.emailSignature) }
  }
  
  // MARK: - Rate Limiting
  
  @Published var maxEmailsPerBatch: Int {
    didSet { defaults.set(maxEmailsPerBatch, forKey: Keys.maxEmailsPerBatch) }
  }
  
  @Published var minPauseBetweenEmails: Double {
    didSet { defaults.set(minPauseBetweenEmails, forKey: Keys.minPause) }
  }
  
  @Published var maxPauseBetweenEmails: Double {
    didSet { defaults.set(maxPauseBetweenEmails, forKey: Keys.maxPause) }
  }
  
  @Published var dailyEmailLimit: Int {
    didSet { defaults.set(dailyEmailLimit, forKey: Keys.dailyLimit) }
  }
  
  // MARK: - Follow-Up Settings
  
  @Published var followUpDaysAfterSend: Int {
    didSet { defaults.set(followUpDaysAfterSend, forKey: Keys.followUpDays) }
  }
  
  @Published var maxFollowUps: Int {
    didSet { defaults.set(maxFollowUps, forKey: Keys.maxFollowUps) }
  }
  
  @Published var autoFollowUpEnabled: Bool {
    didSet { defaults.set(autoFollowUpEnabled, forKey: Keys.autoFollowUp) }
  }
  
  // MARK: - Compliance
  
  @Published var includeUnsubscribeLink: Bool {
    didSet { defaults.set(includeUnsubscribeLink, forKey: Keys.includeUnsub) }
  }
  
  @Published var unsubscribeEmail: String {
    didSet { defaults.set(unsubscribeEmail, forKey: Keys.unsubEmail) }
  }
  
  // MARK: - API Settings
  
  @Published var perplexityModel: String {
    didSet { defaults.set(perplexityModel, forKey: Keys.pplxModel) }
  }
  
  @Published var maxTokensPerRequest: Int {
    didSet { defaults.set(maxTokensPerRequest, forKey: Keys.maxTokens) }
  }
  
  @Published var apiRetryCount: Int {
    didSet { defaults.set(apiRetryCount, forKey: Keys.retryCount) }
  }
  
  // MARK: - Scheduling
  
  @Published var defaultSendHour: Int {
    didSet { defaults.set(defaultSendHour, forKey: Keys.sendHour) }
  }
  
  @Published var defaultSendMinute: Int {
    didSet { defaults.set(defaultSendMinute, forKey: Keys.sendMinute) }
  }
  
  @Published var sendOnWeekends: Bool {
    didSet { defaults.set(sendOnWeekends, forKey: Keys.sendWeekends) }
  }
  
  // MARK: - Language
  
  @Published var defaultLanguage: String {
    didSet { defaults.set(defaultLanguage, forKey: Keys.language) }
  }
  
  @Published var emailTone: String {
    didSet { defaults.set(emailTone, forKey: Keys.tone) }
  }
  
  // MARK: - Init
  
  private init() {
    self.senderEmail = defaults.string(forKey: Keys.senderEmail) ?? "mf@harpocrates-corp.com"
    self.senderName = defaults.string(forKey: Keys.senderName) ?? "Harpocrates Corp"
    self.companyName = defaults.string(forKey: Keys.companyName) ?? "Harpocrates Corp"
    self.emailSignature = defaults.string(forKey: Keys.emailSignature) ?? ""
    
    self.maxEmailsPerBatch = defaults.integer(forKey: Keys.maxEmailsPerBatch).nonZero ?? 10
    self.minPauseBetweenEmails = defaults.double(forKey: Keys.minPause).nonZero ?? 30.0
    self.maxPauseBetweenEmails = defaults.double(forKey: Keys.maxPause).nonZero ?? 90.0
    self.dailyEmailLimit = defaults.integer(forKey: Keys.dailyLimit).nonZero ?? 50
    
    self.followUpDaysAfterSend = defaults.integer(forKey: Keys.followUpDays).nonZero ?? 5
    self.maxFollowUps = defaults.integer(forKey: Keys.maxFollowUps).nonZero ?? 3
    self.autoFollowUpEnabled = defaults.bool(forKey: Keys.autoFollowUp)
    
    self.includeUnsubscribeLink = defaults.object(forKey: Keys.includeUnsub) == nil ? true : defaults.bool(forKey: Keys.includeUnsub)
    self.unsubscribeEmail = defaults.string(forKey: Keys.unsubEmail) ?? "unsubscribe@harpocrates-corp.com"
    
    self.perplexityModel = defaults.string(forKey: Keys.pplxModel) ?? "sonar-pro"
    self.maxTokensPerRequest = defaults.integer(forKey: Keys.maxTokens).nonZero ?? 4000
    self.apiRetryCount = defaults.integer(forKey: Keys.retryCount).nonZero ?? 3
    
    self.defaultSendHour = defaults.integer(forKey: Keys.sendHour).nonZero ?? 9
    self.defaultSendMinute = defaults.integer(forKey: Keys.sendMinute)
    self.sendOnWeekends = defaults.bool(forKey: Keys.sendWeekends)
    
    self.defaultLanguage = defaults.string(forKey: Keys.language) ?? "de"
    self.emailTone = defaults.string(forKey: Keys.tone) ?? "Professional"
  }
  
  // MARK: - Reset
  
  func resetToDefaults() {
    senderEmail = "mf@harpocrates-corp.com"
    senderName = "Harpocrates Corp"
    companyName = "Harpocrates Corp"
    emailSignature = ""
    maxEmailsPerBatch = 10
    minPauseBetweenEmails = 30.0
    maxPauseBetweenEmails = 90.0
    dailyEmailLimit = 50
    followUpDaysAfterSend = 5
    maxFollowUps = 3
    autoFollowUpEnabled = false
    includeUnsubscribeLink = true
    unsubscribeEmail = "unsubscribe@harpocrates-corp.com"
    perplexityModel = "sonar-pro"
    maxTokensPerRequest = 4000
    apiRetryCount = 3
    defaultSendHour = 9
    defaultSendMinute = 0
    sendOnWeekends = false
    defaultLanguage = "de"
    emailTone = "Professional"
  }
}

// MARK: - Keys

private enum Keys {
  static let senderEmail = "settings.senderEmail"
  static let senderName = "settings.senderName"
  static let companyName = "settings.companyName"
  static let emailSignature = "settings.emailSignature"
  static let maxEmailsPerBatch = "settings.maxEmailsPerBatch"
  static let minPause = "settings.minPauseBetweenEmails"
  static let maxPause = "settings.maxPauseBetweenEmails"
  static let dailyLimit = "settings.dailyEmailLimit"
  static let followUpDays = "settings.followUpDays"
  static let maxFollowUps = "settings.maxFollowUps"
  static let autoFollowUp = "settings.autoFollowUp"
  static let includeUnsub = "settings.includeUnsubscribeLink"
  static let unsubEmail = "settings.unsubscribeEmail"
  static let pplxModel = "settings.perplexityModel"
  static let maxTokens = "settings.maxTokens"
  static let retryCount = "settings.retryCount"
  static let sendHour = "settings.sendHour"
  static let sendMinute = "settings.sendMinute"
  static let sendWeekends = "settings.sendWeekends"
  static let language = "settings.language"
  static let tone = "settings.tone"
}

// MARK: - Helpers

private extension Int {
  var nonZero: Int? { self == 0 ? nil : self }
}

private extension Double {
  var nonZero: Double? { self == 0 ? nil : self }
}
