//
//  LeadScoringService.swift
//  HarpoOutreach
//
//  Lead scoring, duplicate detection, and domain-based deduplication
//

import Foundation

// MARK: - Lead Score

struct LeadScore {
  let total: Int // 0-100
  let factors: [ScoreFactor]
  let tier: ScoreTier
  
  enum ScoreTier: String {
    case hot = "Hot"
    case warm = "Warm"
    case cold = "Cold"
    case disqualified = "Disqualified"
    
    var color: String {
      switch self {
      case .hot: return "red"
      case .warm: return "orange"
      case .cold: return "blue"
      case .disqualified: return "gray"
      }
    }
  }
}

struct ScoreFactor {
  let name: String
  let points: Int
  let reason: String
}

// MARK: - Duplicate Result

struct DuplicateCheckResult {
  let isDuplicate: Bool
  let matchType: MatchType
  let matchedCompany: String?
  let similarity: Double
  
  enum MatchType: String {
    case exact = "Exact Match"
    case domain = "Domain Match"
    case fuzzy = "Fuzzy Name Match"
    case none = "No Match"
  }
}

// MARK: - Service

class LeadScoringService {
  
  static let shared = LeadScoringService()
  
  // Persistent blocklist of contacted domains
  private var contactedDomains: Set<String> = []
  private var contactedNames: Set<String> = []
  private let blocklist = BlocklistManager()
  
  // MARK: - Lead Scoring
  
  func scoreLead(
    name: String,
    title: String,
    company: String,
    industry: String,
    companySize: String,
    website: String,
    emailVerified: Bool,
    hasLinkedIn: Bool,
    researchAvailable: Bool
  ) -> LeadScore {
    var factors: [ScoreFactor] = []
    var total = 0
    
    // Title relevance (0-25 points)
    let titleScore = scoreTitleRelevance(title)
    factors.append(ScoreFactor(name: "Title", points: titleScore, reason: titleRelevanceReason(title)))
    total += titleScore
    
    // Company size fit (0-20 points)
    let sizeScore = scoreCompanySize(companySize)
    factors.append(ScoreFactor(name: "Company Size", points: sizeScore, reason: "Size: \(companySize)"))
    total += sizeScore
    
    // Industry fit (0-20 points)
    let industryScore = scoreIndustry(industry)
    factors.append(ScoreFactor(name: "Industry", points: industryScore, reason: "Industry: \(industry)"))
    total += industryScore
    
    // Data quality (0-20 points)
    var dataScore = 0
    if emailVerified { dataScore += 10 }
    if hasLinkedIn { dataScore += 5 }
    if researchAvailable { dataScore += 5 }
    factors.append(ScoreFactor(name: "Data Quality", points: dataScore, reason: "Email: \(emailVerified), LinkedIn: \(hasLinkedIn)"))
    total += dataScore
    
    // Website presence (0-15 points)
    let webScore = website.isEmpty ? 0 : 15
    factors.append(ScoreFactor(name: "Web Presence", points: webScore, reason: website.isEmpty ? "No website" : "Has website"))
    total += webScore
    
    total = min(total, 100)
    
    let tier: LeadScore.ScoreTier
    switch total {
    case 70...100: tier = .hot
    case 40...69: tier = .warm
    case 1...39: tier = .cold
    default: tier = .disqualified
    }
    
    return LeadScore(total: total, factors: factors, tier: tier)
  }
  
  // MARK: - Duplicate Detection
  
  func checkDuplicate(
    companyName: String,
    domain: String,
    existingCompanies: [(name: String, domain: String)]
  ) -> DuplicateCheckResult {
    let normalizedDomain = normalizeDomain(domain)
    let normalizedName = companyName.lowercased().trimmingCharacters(in: .whitespaces)
    
    // 1. Exact domain match (highest confidence)
    if !normalizedDomain.isEmpty {
      for existing in existingCompanies {
        let existingDomain = normalizeDomain(existing.domain)
        if !existingDomain.isEmpty && existingDomain == normalizedDomain {
          return DuplicateCheckResult(
            isDuplicate: true,
            matchType: .domain,
            matchedCompany: existing.name,
            similarity: 1.0
          )
        }
      }
      
      // Check blocklist
      if contactedDomains.contains(normalizedDomain) {
        return DuplicateCheckResult(
          isDuplicate: true,
          matchType: .domain,
          matchedCompany: "[Blocklist]",
          similarity: 1.0
        )
      }
    }
    
    // 2. Exact name match
    for existing in existingCompanies {
      let existingName = existing.name.lowercased().trimmingCharacters(in: .whitespaces)
      if existingName == normalizedName {
        return DuplicateCheckResult(
          isDuplicate: true,
          matchType: .exact,
          matchedCompany: existing.name,
          similarity: 1.0
        )
      }
    }
    
    // 3. Fuzzy name match (Levenshtein)
    for existing in existingCompanies {
      let similarity = levenshteinSimilarity(
        normalizedName,
        existing.name.lowercased().trimmingCharacters(in: .whitespaces)
      )
      if similarity > 0.85 {
        return DuplicateCheckResult(
          isDuplicate: true,
          matchType: .fuzzy,
          matchedCompany: existing.name,
          similarity: similarity
        )
      }
    }
    
    return DuplicateCheckResult(
      isDuplicate: false,
      matchType: .none,
      matchedCompany: nil,
      similarity: 0
    )
  }
  
  // MARK: - Blocklist Management
  
  func addToBlocklist(domain: String, companyName: String) {
    let normalized = normalizeDomain(domain)
    if !normalized.isEmpty { contactedDomains.insert(normalized) }
    contactedNames.insert(companyName.lowercased())
    blocklist.save(domains: contactedDomains, names: contactedNames)
  }
  
  func loadBlocklist() {
    let saved = blocklist.load()
    contactedDomains = saved.domains
    contactedNames = saved.names
  }
  
  func isBlocked(domain: String) -> Bool {
    return contactedDomains.contains(normalizeDomain(domain))
  }
  
  func blocklistCount() -> Int {
    return contactedDomains.count
  }
  
  // MARK: - Private Scoring Helpers
  
  private func scoreTitleRelevance(_ title: String) -> Int {
    let t = title.lowercased()
    let cLevel = ["ceo", "cto", "cfo", "ciso", "coo", "chief"]
    let vpLevel = ["vp", "vice president", "director"]
    let headLevel = ["head of", "leiter", "manager", "lead"]
    
    if cLevel.contains(where: { t.contains($0) }) { return 25 }
    if vpLevel.contains(where: { t.contains($0) }) { return 20 }
    if headLevel.contains(where: { t.contains($0) }) { return 15 }
    return 5
  }
  
  private func titleRelevanceReason(_ title: String) -> String {
    let t = title.lowercased()
    if ["ceo", "cto", "ciso", "chief"].contains(where: { t.contains($0) }) {
      return "C-Level decision maker"
    }
    if ["vp", "director"].contains(where: { t.contains($0) }) {
      return "VP/Director level"
    }
    return "Other title"
  }
  
  private func scoreCompanySize(_ size: String) -> Int {
    let s = size.lowercased()
    if s.contains("enterprise") || s.contains("1000+") || s.contains("10000") { return 20 }
    if s.contains("mid") || s.contains("200") || s.contains("500") { return 15 }
    if s.contains("small") || s.contains("50") || s.contains("startup") { return 10 }
    return 5
  }
  
  private func scoreIndustry(_ industry: String) -> Int {
    let i = industry.lowercased()
    let highPriority = ["banking", "finance", "insurance", "fintech", "regtech"]
    let medPriority = ["healthcare", "pharma", "energy", "telecom"]
    
    if highPriority.contains(where: { i.contains($0) }) { return 20 }
    if medPriority.contains(where: { i.contains($0) }) { return 15 }
    return 10
  }
  
  // MARK: - String Helpers
  
  private func normalizeDomain(_ domain: String) -> String {
    var d = domain.lowercased().trimmingCharacters(in: .whitespaces)
    d = d.replacingOccurrences(of: "https://", with: "")
    d = d.replacingOccurrences(of: "http://", with: "")
    d = d.replacingOccurrences(of: "www.", with: "")
    if let slash = d.firstIndex(of: "/") { d = String(d[d.startIndex..<slash]) }
    return d
  }
  
  func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
    let distance = levenshteinDistance(s1, s2)
    let maxLen = max(s1.count, s2.count)
    guard maxLen > 0 else { return 1.0 }
    return 1.0 - (Double(distance) / Double(maxLen))
  }
  
  private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let a = Array(s1)
    let b = Array(s2)
    let m = a.count
    let n = b.count
    
    if m == 0 { return n }
    if n == 0 { return m }
    
    var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
    
    for i in 0...m { matrix[i][0] = i }
    for j in 0...n { matrix[0][j] = j }
    
    for i in 1...m {
      for j in 1...n {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        matrix[i][j] = min(
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost
        )
      }
    }
    
    return matrix[m][n]
  }
}

// MARK: - Blocklist Persistence

private class BlocklistManager {
  
  private let fileURL: URL = {
    let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("HarpoOutreach", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("blocklist.json")
  }()
  
  func save(domains: Set<String>, names: Set<String>) {
    let data: [String: [String]] = [
      "domains": Array(domains),
      "names": Array(names)
    ]
    if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
      // Atomic write: write to temp then rename
      let tempURL = fileURL.appendingPathExtension("tmp")
      try? jsonData.write(to: tempURL, options: .atomic)
      try? FileManager.default.moveItem(at: tempURL, to: fileURL)
    }
  }
  
  func load() -> (domains: Set<String>, names: Set<String>) {
    guard let data = try? Data(contentsOf: fileURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
      return ([], [])
    }
    return (
      Set(json["domains"] ?? []),
      Set(json["names"] ?? [])
    )
  }
}
