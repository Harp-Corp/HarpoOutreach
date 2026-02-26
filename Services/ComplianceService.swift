//
//  ComplianceService.swift
//  HarpoOutreach
//
//  GDPR/DSGVO compliance: opt-out tracking, unsubscribe links, blocklist
//

import Foundation

// MARK: - Opt-Out Record

struct OptOutRecord: Codable, Identifiable {
  let id: UUID
  let email: String
  let domain: String
  let reason: OptOutReason
  let timestamp: Date
  let source: OptOutSource
  
  init(
    email: String,
    domain: String = "",
    reason: OptOutReason = .unsubscribed,
    source: OptOutSource = .manual
  ) {
    self.id = UUID()
    self.email = email.lowercased()
    self.domain = domain.lowercased()
    self.reason = reason
    self.timestamp = Date()
    self.source = source
  }
}

enum OptOutReason: String, Codable {
  case unsubscribed = "Unsubscribed"
  case bounced = "Bounced"
  case complained = "Spam Complaint"
  case manual = "Manually Removed"
  case legalRequest = "Legal/DSGVO Request"
}

enum OptOutSource: String, Codable {
  case unsubscribeLink = "Unsubscribe Link"
  case replyKeyword = "Reply Keyword"
  case manual = "Manual"
  case bounceDetection = "Bounce Detection"
  case importedList = "Imported Blocklist"
}

// MARK: - Compliance Service

class ComplianceService {
  
  static let shared = ComplianceService()
  
  private var optOutList: [OptOutRecord] = []
  private var blockedEmails: Set<String> = []
  private var blockedDomains: Set<String> = []
  
  private let storageURL: URL = {
    let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("HarpoOutreach", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("optout_list.json")
  }()
  
  init() {
    loadOptOutList()
  }
  
  // MARK: - Unsubscribe Link Generation
  
  func generateUnsubscribeFooter(forEmail recipientEmail: String, senderName: String = "Harpocrates Corp") -> String {
    let encoded = recipientEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recipientEmail
    let unsubLink = "mailto:unsubscribe@harpocrates-corp.com?subject=Unsubscribe&body=Please%20remove%20\(encoded)%20from%20your%20mailing%20list"
    
    var footer = "\n\n---\n"
    footer += "Diese Email wurde von \(senderName) gesendet.\n"
    footer += "Wenn Sie keine weiteren Emails erhalten moechten: \(unsubLink)\n"
    footer += "Oder antworten Sie mit 'Unsubscribe' / 'Abmelden'.\n"
    return footer
  }
  
  // MARK: - List-Unsubscribe MIME Header
  
  func generateListUnsubscribeHeader(recipientEmail: String) -> [String: String] {
    let encoded = recipientEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recipientEmail
    let mailtoUnsub = "mailto:unsubscribe@harpocrates-corp.com?subject=Unsubscribe%20\(encoded)"
    
    return [
      "List-Unsubscribe": "<\(mailtoUnsub)>",
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click"
    ]
  }
  
  // MARK: - Opt-Out Management
  
  func addOptOut(email: String, domain: String = "", reason: OptOutReason = .unsubscribed, source: OptOutSource = .manual) {
    let record = OptOutRecord(email: email, domain: domain, reason: reason, source: source)
    optOutList.append(record)
    blockedEmails.insert(email.lowercased())
    if !domain.isEmpty {
      blockedDomains.insert(domain.lowercased())
    }
    saveOptOutList()
  }
  
  func removeOptOut(email: String) {
    optOutList.removeAll { $0.email == email.lowercased() }
    blockedEmails.remove(email.lowercased())
    saveOptOutList()
  }
  
  func isOptedOut(email: String) -> Bool {
    return blockedEmails.contains(email.lowercased())
  }
  
  func isDomainBlocked(domain: String) -> Bool {
    return blockedDomains.contains(domain.lowercased())
  }
  
  // MARK: - Pre-Send Compliance Check
  
  func canSendTo(email: String, domain: String = "") -> ComplianceCheckResult {
    if isOptedOut(email: email) {
      return ComplianceCheckResult(
        allowed: false,
        reason: "Email is on opt-out list",
        regulation: "DSGVO Art. 21"
      )
    }
    
    if !domain.isEmpty && isDomainBlocked(domain: domain) {
      return ComplianceCheckResult(
        allowed: false,
        reason: "Domain is blocked",
        regulation: "DSGVO Art. 21"
      )
    }
    
    return ComplianceCheckResult(allowed: true, reason: "OK", regulation: nil)
  }
  
  // MARK: - Reply-Based Opt-Out Detection
  
  func detectOptOutInReply(replyBody: String, senderEmail: String) -> Bool {
    let keywords = [
      "unsubscribe", "abmelden", "abbestellen",
      "opt out", "opt-out", "remove me",
      "keine emails", "no more emails",
      "stopp", "stop", "bitte entfernen",
      "nicht mehr kontaktieren", "do not contact",
      "loeschen sie meine daten", "delete my data",
      "dsgvo", "gdpr", "widerspruch"
    ]
    
    let lowered = replyBody.lowercased()
    for keyword in keywords {
      if lowered.contains(keyword) {
        addOptOut(
          email: senderEmail,
          reason: .unsubscribed,
          source: .replyKeyword
        )
        return true
      }
    }
    return false
  }
  
  // MARK: - Batch Compliance Filter
  
  func filterCompliantLeads(emails: [(email: String, domain: String)]) -> [(email: String, domain: String, blocked: Bool)] {
    return emails.map { lead in
      let check = canSendTo(email: lead.email, domain: lead.domain)
      return (lead.email, lead.domain, !check.allowed)
    }
  }
  
  // MARK: - Statistics
  
  func optOutCount() -> Int { return optOutList.count }
  
  func optOutsByReason() -> [OptOutReason: Int] {
    var counts: [OptOutReason: Int] = [:]
    for record in optOutList {
      counts[record.reason, default: 0] += 1
    }
    return counts
  }
  
  func recentOptOuts(days: Int = 30) -> [OptOutRecord] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    return optOutList.filter { $0.timestamp > cutoff }
  }
  
  // MARK: - Persistence
  
  private func saveOptOutList() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(optOutList) else { return }
    
    let tempURL = storageURL.appendingPathExtension("tmp")
    try? data.write(to: tempURL, options: .atomic)
    try? FileManager.default.replaceItemAt(storageURL, withItemAt: tempURL)
  }
  
  private func loadOptOutList() {
    guard let data = try? Data(contentsOf: storageURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let list = try? decoder.decode([OptOutRecord].self, from: data) else { return }
    optOutList = list
    blockedEmails = Set(list.map { $0.email })
    blockedDomains = Set(list.compactMap { $0.domain.isEmpty ? nil : $0.domain })
  }
  
  // MARK: - Export for Audit
  
  func exportOptOutListCSV() -> String {
    var csv = "Email,Domain,Reason,Source,Timestamp\n"
    let formatter = ISO8601DateFormatter()
    for record in optOutList {
      csv += "\(record.email),\(record.domain),\(record.reason.rawValue),\(record.source.rawValue),\(formatter.string(from: record.timestamp))\n"
    }
    return csv
  }
}

// MARK: - Compliance Check Result

struct ComplianceCheckResult {
  let allowed: Bool
  let reason: String
  let regulation: String?
}
