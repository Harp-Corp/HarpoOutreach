import Foundation
import Combine

// MARK: - BlocklistManager
// Advanced blocklist management with pattern matching, import/export,
// and automatic domain extraction. Works with DataStore for persistence.

@MainActor
class BlocklistManager: ObservableObject {

  static let shared = BlocklistManager()

  @Published var blockedEmails: Set<String> = []
  @Published var blockedDomains: Set<String> = []
  @Published var blocklistHistory: [BlocklistEntry] = []

  // MARK: - Blocking Logic

  /// Checks if an email or domain is blocked.
  func isBlocked(email: String) -> Bool {
    let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if blockedEmails.contains(normalized) { return true }
    if let domain = extractDomain(from: normalized), blockedDomains.contains(domain) { return true }
    return false
  }

  /// Checks if a domain is blocked.
  func isDomainBlocked(_ domain: String) -> Bool {
    return blockedDomains.contains(domain.lowercased())
  }

  // MARK: - Adding to Blocklist

  /// Blocks a specific email address.
  func blockEmail(_ email: String, reason: BlockReason = .manual) {
    let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.contains("@") else { return }
    blockedEmails.insert(normalized)
    addHistoryEntry(value: normalized, type: .email, reason: reason)
  }

  /// Blocks an entire domain.
  func blockDomain(_ domain: String, reason: BlockReason = .manual) {
    let normalized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    blockedDomains.insert(normalized)
    addHistoryEntry(value: normalized, type: .domain, reason: reason)
  }

  /// Auto-blocks email and optionally the domain.
  func blockEmailAndDomain(_ email: String, blockDomainToo: Bool = false, reason: BlockReason = .manual) {
    blockEmail(email, reason: reason)
    if blockDomainToo, let domain = extractDomain(from: email) {
      blockDomain(domain, reason: reason)
    }
  }

  // MARK: - Removing from Blocklist

  /// Unblocks a specific email address.
  func unblockEmail(_ email: String) {
    blockedEmails.remove(email.lowercased())
  }

  /// Unblocks a domain.
  func unblockDomain(_ domain: String) {
    blockedDomains.remove(domain.lowercased())
  }

  // MARK: - Bulk Operations

  /// Blocks multiple emails at once.
  func blockEmails(_ emails: [String], reason: BlockReason = .imported) {
    for email in emails {
      blockEmail(email, reason: reason)
    }
  }

  /// Blocks multiple domains at once.
  func blockDomains(_ domains: [String], reason: BlockReason = .imported) {
    for domain in domains {
      blockDomain(domain, reason: reason)
    }
  }

  /// Imports blocklist from CSV content (one entry per line).
  func importFromCSV(_ content: String) -> Int {
    let lines = content.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var imported = 0
    for line in lines {
      if line.contains("@") {
        blockEmail(line, reason: .imported)
      } else if line.contains(".") {
        blockDomain(line, reason: .imported)
      }
      imported += 1
    }
    return imported
  }

  /// Exports blocklist as CSV string.
  func exportToCSV() -> String {
    var lines: [String] = []
    lines.append("type,value,blocked_at")
    for email in blockedEmails.sorted() {
      lines.append("email,\(email),")
    }
    for domain in blockedDomains.sorted() {
      lines.append("domain,\(domain),")
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Filtering

  /// Filters an array of leads, removing blocked ones.
  func filterBlocked(leads: [Lead]) -> [Lead] {
    return leads.filter { !isBlocked(email: $0.email) }
  }

  /// Returns count of how many leads would be blocked.
  func countBlocked(in leads: [Lead]) -> Int {
    return leads.filter { isBlocked(email: $0.email) }.count
  }

  // MARK: - Statistics

  var totalBlockedCount: Int {
    blockedEmails.count + blockedDomains.count
  }

  var recentBlocks: [BlocklistEntry] {
    Array(blocklistHistory.suffix(20).reversed())
  }

  // MARK: - Helpers

  private func extractDomain(from email: String) -> String? {
    let parts = email.split(separator: "@")
    guard parts.count == 2 else { return nil }
    return String(parts[1]).lowercased()
  }

  private func addHistoryEntry(value: String, type: BlockType, reason: BlockReason) {
    let entry = BlocklistEntry(value: value, type: type, reason: reason, blockedAt: Date())
    blocklistHistory.append(entry)
    // Keep history manageable
    if blocklistHistory.count > 500 {
      blocklistHistory = Array(blocklistHistory.suffix(400))
    }
  }
}

// MARK: - Supporting Types

struct BlocklistEntry: Identifiable, Codable {
  let id: UUID
  let value: String
  let type: BlockType
  let reason: BlockReason
  let blockedAt: Date

  init(value: String, type: BlockType, reason: BlockReason, blockedAt: Date) {
    self.id = UUID()
    self.value = value
    self.type = type
    self.reason = reason
    self.blockedAt = blockedAt
  }
}

enum BlockType: String, Codable {
  case email = "Email"
  case domain = "Domain"
}

enum BlockReason: String, Codable {
  case manual = "Manual"
  case bounced = "Bounced"
  case unsubscribed = "Unsubscribed"
  case imported = "Imported"
  case spamComplaint = "SpamComplaint"
  case optOut = "OptOut"
}
