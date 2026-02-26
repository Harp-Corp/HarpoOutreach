//
//  EmailPipelineViewModel.swift
//  HarpoOutreach
//
//  Extracted from AppViewModel: Email drafting, approval, sending pipeline
//

import Foundation
import Combine

@MainActor
class EmailPipelineViewModel: ObservableObject {
  
  // MARK: - Published State
  
  @Published var drafts: [EmailDraft] = []
  @Published var approvedEmails: [EmailDraft] = []
  @Published var sentEmails: [EmailDraft] = []
  @Published var isDrafting: Bool = false
  @Published var isSending: Bool = false
  @Published var sendProgress: Double = 0
  @Published var lastError: String?
  
  // MARK: - Dependencies
  
  private let dataStore = DataStore.shared
  private let settings = AppSettings.shared
  private let compliance = ComplianceService.shared
  private let rateLimiter = RateLimiter.shared
  private let tracking = DeliveryTrackingService.shared
  private let personalization = PersonalizationEngine.shared
  
  // MARK: - Draft Email
  
  func draftEmail(for lead: Lead, research: String) async -> EmailDraft? {
    isDrafting = true
    defer { isDrafting = false }
    
    // Compliance check
    let check = compliance.canSendTo(email: lead.email, domain: lead.website ?? "")
    guard check.allowed else {
      lastError = "Compliance blocked: \(check.reason)"
      return nil
    }
    
    // Build personalization context
    let context = PersonalizationContext(
      leadName: lead.name,
      leadTitle: lead.title ?? "",
      company: lead.company,
      industry: "",
      website: lead.website ?? "",
      researchSummary: research,
      language: settings.defaultLanguage
    )
    
    let prompt = personalization.buildPersonalizationPrompt(
      context: context,
      product: "Compliance-Automatisierung"
    )
    
    do {
      let emailContent = try await PerplexityService.draftEmail(
        prompt: prompt
      )
      
      // Add unsubscribe footer if enabled
      var body = emailContent
      if settings.includeUnsubscribeLink {
        body += compliance.generateUnsubscribeFooter(
          forEmail: lead.email,
          senderName: settings.senderName
        )
      }
      
      // Generate subject variants
      let hooks = personalization.extractHooks(from: research, company: lead.company)
      let subjects = personalization.generateSubjectVariants(
        context: context,
        hooks: hooks
      )
      
      let draft = EmailDraft(
        leadID: lead.id,
        to: lead.email,
        subject: subjects.first ?? "Partnerschaft: \(lead.company)",
        body: body,
        subjectVariants: subjects,
        status: .draft
      )
      
      drafts.append(draft)
      return draft
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }
  
  // MARK: - Approve
  
  func approveDraft(_ draft: EmailDraft) {
    if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
      drafts[idx].status = .approved
      approvedEmails.append(drafts[idx])
      drafts.remove(at: idx)
    }
  }
  
  func rejectDraft(_ draft: EmailDraft) {
    drafts.removeAll { $0.id == draft.id }
  }
  
  // MARK: - Send Batch
  
  func sendApprovedBatch() async {
    isSending = true
    sendProgress = 0
    
    let batch = Array(approvedEmails.prefix(settings.maxEmailsPerBatch))
    let total = batch.count
    
    for (index, email) in batch.enumerated() {
      // Rate limit check
      let canSend = await rateLimiter.tryAcquire(domain: "gmail")
      guard canSend else {
        lastError = "Rate limit reached. Pausing."
        break
      }
      
      do {
        // Get MIME headers for unsubscribe
        let headers = compliance.generateListUnsubscribeHeader(
          recipientEmail: email.to
        )
        
        let messageID = try await GmailService.shared.sendEmail(
          to: email.to,
          subject: email.subject,
          body: email.body,
          from: settings.senderEmail,
          headers: headers
        )
        
        // Track delivery
        tracking.trackSend(
          messageID: messageID,
          recipientEmail: email.to
        )
        
        sentEmails.append(email)
        approvedEmails.removeAll { $0.id == email.id }
        
      } catch {
        lastError = "Send failed for \(email.to): \(error.localizedDescription)"
      }
      
      sendProgress = Double(index + 1) / Double(total)
      
      // Random pause between sends
      let pause = Double.random(
        in: settings.minPauseBetweenEmails...settings.maxPauseBetweenEmails
      )
      try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
    }
    
    isSending = false
  }
  
  // MARK: - Stats
  
  var draftCount: Int { drafts.count }
  var approvedCount: Int { approvedEmails.count }
  var sentCount: Int { sentEmails.count }
}

// MARK: - Email Draft Model

struct EmailDraft: Identifiable {
  let id: UUID
  let leadID: UUID
  let to: String
  var subject: String
  var body: String
  var subjectVariants: [String]
  var status: DraftStatus
  var sentAt: Date?
  
  init(
    leadID: UUID,
    to: String,
    subject: String,
    body: String,
    subjectVariants: [String] = [],
    status: DraftStatus = .draft
  ) {
    self.id = UUID()
    self.leadID = leadID
    self.to = to
    self.subject = subject
    self.body = body
    self.subjectVariants = subjectVariants
    self.status = status
    self.sentAt = nil
  }
  
  enum DraftStatus: String {
    case draft = "Draft"
    case approved = "Approved"
    case sent = "Sent"
    case failed = "Failed"
  }
}
