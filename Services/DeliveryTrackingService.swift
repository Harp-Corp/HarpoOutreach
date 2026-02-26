//
//  DeliveryTrackingService.swift
//  HarpoOutreach
//
//  Email bounce detection, delivery verification via Gmail API
//

import Foundation

// MARK: - Delivery Status

enum DeliveryStatus: String, Codable {
  case sent = "Sent"
  case delivered = "Delivered"
  case bounced = "Bounced"
  case spamComplaint = "Spam Complaint"
  case failed = "Failed"
  case pending = "Pending"
  case unknown = "Unknown"
  
  var icon: String {
    switch self {
    case .sent: return "paperplane"
    case .delivered: return "checkmark.circle"
    case .bounced: return "exclamationmark.triangle"
    case .spamComplaint: return "xmark.shield"
    case .failed: return "xmark.circle"
    case .pending: return "clock"
    case .unknown: return "questionmark.circle"
    }
  }
}

// MARK: - Delivery Record

struct DeliveryRecord: Codable, Identifiable {
  let id: UUID
  let messageID: String
  let recipientEmail: String
  let sentAt: Date
  var status: DeliveryStatus
  var lastChecked: Date
  var bounceReason: String?
  var gmailThreadID: String?
  
  init(messageID: String, recipientEmail: String, gmailThreadID: String? = nil) {
    self.id = UUID()
    self.messageID = messageID
    self.recipientEmail = recipientEmail
    self.sentAt = Date()
    self.status = .sent
    self.lastChecked = Date()
    self.bounceReason = nil
    self.gmailThreadID = gmailThreadID
  }
}

// MARK: - Bounce Patterns

private let bounceSubjects = [
  "delivery status notification", "undeliverable",
  "mail delivery failed", "returned mail",
  "failure notice", "delivery failure"
]

private let bounceBody = [
  "550 user not found", "550 no such user",
  "mailbox not found", "address rejected",
  "user unknown", "does not exist",
  "invalid recipient", "550 5.1.1"
]

// MARK: - Service

class DeliveryTrackingService {
  static let shared = DeliveryTrackingService()
  private var records: [DeliveryRecord] = []
  
  private let storageURL: URL = {
    let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("HarpoOutreach", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("delivery_tracking.json")
  }()
  
  init() { loadRecords() }
  
  // MARK: - Track New Send
  
  func trackSend(messageID: String, recipientEmail: String, gmailThreadID: String? = nil) {
    let record = DeliveryRecord(messageID: messageID, recipientEmail: recipientEmail, gmailThreadID: gmailThreadID)
    records.append(record)
    saveRecords()
  }
  
  // MARK: - Bounce Detection
  
  func checkForBounces(inboxMessages: [(subject: String, body: String, from: String)]) -> [String] {
    var bouncedEmails: [String] = []
    for msg in inboxMessages {
      let subj = msg.subject.lowercased()
      let body = msg.body.lowercased()
      let from = msg.from.lowercased()
      
      let isDaemon = from.contains("mailer-daemon") || from.contains("postmaster")
      let subjMatch = bounceSubjects.contains { subj.contains($0) }
      let bodyMatch = bounceBody.contains { body.contains($0) }
      
      if isDaemon || (subjMatch && bodyMatch) {
        if let email = extractBouncedEmail(from: msg.body) {
          markAsBounced(email: email, reason: msg.subject)
          bouncedEmails.append(email)
        }
      }
    }
    return bouncedEmails
  }
  
  // MARK: - Gmail Sent Verification
  
  func verifySentStatus(messageID: String, isInSentFolder: Bool) {
    guard let idx = records.firstIndex(where: { $0.messageID == messageID }) else { return }
    records[idx].status = isInSentFolder ? .delivered : .failed
    records[idx].lastChecked = Date()
    saveRecords()
  }
  
  // MARK: - Status Updates
  
  func markAsBounced(email: String, reason: String) {
    for i in records.indices where records[i].recipientEmail.lowercased() == email.lowercased() {
      records[i].status = .bounced
      records[i].bounceReason = reason
      records[i].lastChecked = Date()
    }
    saveRecords()
    ComplianceService.shared.addOptOut(email: email, reason: .bounced, source: .bounceDetection)
  }
  
  func markAsSpamComplaint(email: String) {
    for i in records.indices where records[i].recipientEmail.lowercased() == email.lowercased() {
      records[i].status = .spamComplaint
      records[i].lastChecked = Date()
    }
    saveRecords()
    ComplianceService.shared.addOptOut(email: email, reason: .complained, source: .bounceDetection)
  }
  
  // MARK: - Queries
  
  func getStatus(forEmail email: String) -> DeliveryStatus {
    records.last(where: { $0.recipientEmail.lowercased() == email.lowercased() })?.status ?? .unknown
  }
  
  func bouncedEmails() -> [String] {
    records.filter { $0.status == .bounced }.map { $0.recipientEmail }
  }
  
  func recentRecords(days: Int = 7) -> [DeliveryRecord] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    return records.filter { $0.sentAt > cutoff }
  }
  
  func staleRecords() -> [DeliveryRecord] {
    let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
    return records.filter { $0.status == .sent && $0.lastChecked < cutoff }
  }
  
  // MARK: - Statistics
  
  func deliveryStats() -> DeliveryStats {
    var s = DeliveryStats()
    s.total = records.count
    for r in records {
      switch r.status {
      case .sent: s.sent += 1
      case .delivered: s.delivered += 1
      case .bounced: s.bounced += 1
      case .spamComplaint: s.complaints += 1
      case .failed: s.failed += 1
      case .pending: s.pending += 1
      case .unknown: break
      }
    }
    return s
  }
  
  // MARK: - Private
  
  private func extractBouncedEmail(from body: String) -> String? {
    let pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(body.startIndex..., in: body)
    let matches = regex.matches(in: body, range: range)
    let skip = ["mailer-daemon", "postmaster", "noreply"]
    for match in matches {
      if let r = Range(match.range, in: body) {
        let email = String(body[r]).lowercased()
        if !skip.contains(where: { email.contains($0) }) { return email }
      }
    }
    return nil
  }
  
  private func saveRecords() {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    guard let data = try? enc.encode(records) else { return }
    try? data.write(to: storageURL, options: .atomic)
  }
  
  private func loadRecords() {
    guard let data = try? Data(contentsOf: storageURL) else { return }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    records = (try? dec.decode([DeliveryRecord].self, from: data)) ?? []
  }
}

// MARK: - Stats Model

struct DeliveryStats {
  var total = 0
  var sent = 0
  var delivered = 0
  var bounced = 0
  var complaints = 0
  var failed = 0
  var pending = 0
  
  var deliveryRate: Double {
    guard total > 0 else { return 0 }
    return Double(delivered) / Double(total) * 100
  }
  var bounceRate: Double {
    guard total > 0 else { return 0 }
    return Double(bounced) / Double(total) * 100
  }
}
