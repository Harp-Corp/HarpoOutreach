//
//  CacheService.swift
//  HarpoOutreach
//
//  Intelligent caching layer for API responses and computed data
//

import Foundation

// MARK: - Cache Entry

struct CacheEntry<T> {
  let value: T
  let timestamp: Date
  let ttl: TimeInterval
  
  var isExpired: Bool {
    Date().timeIntervalSince(timestamp) > ttl
  }
  
  var age: TimeInterval {
    Date().timeIntervalSince(timestamp)
  }
}

// MARK: - Cache Key

enum CacheKey: String, CaseIterable {
  case perplexityResearch = "perplexity_research"
  case companyData = "company_data"
  case emailDraft = "email_draft"
  case leadEnrichment = "lead_enrichment"
  case templateRendered = "template_rendered"
  case analyticsSnapshot = "analytics_snapshot"
  
  var defaultTTL: TimeInterval {
    switch self {
    case .perplexityResearch: return 24 * 3600  // 24h
    case .companyData: return 7 * 24 * 3600     // 7 days
    case .emailDraft: return 3600               // 1h
    case .leadEnrichment: return 48 * 3600      // 48h
    case .templateRendered: return 1800         // 30min
    case .analyticsSnapshot: return 300         // 5min
    }
  }
}

// MARK: - Cache Statistics

struct CacheStats {
  var hits: Int = 0
  var misses: Int = 0
  var evictions: Int = 0
  var totalEntries: Int = 0
  var memoryEstimateBytes: Int = 0
  
  var hitRate: Double {
    let total = hits + misses
    guard total > 0 else { return 0 }
    return Double(hits) / Double(total) * 100
  }
}

// MARK: - Cache Service

actor CacheService {
  static let shared = CacheService()
  
  private var stringCache: [String: CacheEntry<String>] = [:]
  private var dataCache: [String: CacheEntry<Data>] = [:]
  private var jsonCache: [String: CacheEntry<[String: Any]>] = [:]
  
  private var stats = CacheStats()
  private let maxEntries = 500
  
  // MARK: - String Cache
  
  func cacheString(_ value: String, forKey key: String, category: CacheKey, ttl: TimeInterval? = nil) {
    let effectiveTTL = ttl ?? category.defaultTTL
    let compositeKey = "\(category.rawValue):\(key)"
    stringCache[compositeKey] = CacheEntry(value: value, timestamp: Date(), ttl: effectiveTTL)
    enforceLimit()
    updateEntryCount()
  }
  
  func getString(forKey key: String, category: CacheKey) -> String? {
    let compositeKey = "\(category.rawValue):\(key)"
    guard let entry = stringCache[compositeKey] else {
      stats.misses += 1
      return nil
    }
    if entry.isExpired {
      stringCache.removeValue(forKey: compositeKey)
      stats.misses += 1
      stats.evictions += 1
      return nil
    }
    stats.hits += 1
    return entry.value
  }
  
  // MARK: - Data Cache
  
  func cacheData(_ value: Data, forKey key: String, category: CacheKey, ttl: TimeInterval? = nil) {
    let effectiveTTL = ttl ?? category.defaultTTL
    let compositeKey = "\(category.rawValue):\(key)"
    dataCache[compositeKey] = CacheEntry(value: value, timestamp: Date(), ttl: effectiveTTL)
    enforceLimit()
    updateEntryCount()
  }
  
  func getData(forKey key: String, category: CacheKey) -> Data? {
    let compositeKey = "\(category.rawValue):\(key)"
    guard let entry = dataCache[compositeKey] else {
      stats.misses += 1
      return nil
    }
    if entry.isExpired {
      dataCache.removeValue(forKey: compositeKey)
      stats.misses += 1
      stats.evictions += 1
      return nil
    }
    stats.hits += 1
    return entry.value
  }
  
  // MARK: - Research Cache (Perplexity API)
  
  func cacheResearch(forCompany company: String, research: String) {
    let key = company.lowercased().trimmingCharacters(in: .whitespaces)
    cacheString(research, forKey: key, category: .perplexityResearch)
  }
  
  func getCachedResearch(forCompany company: String) -> String? {
    let key = company.lowercased().trimmingCharacters(in: .whitespaces)
    return getString(forKey: key, category: .perplexityResearch)
  }
  
  // MARK: - Email Draft Cache
  
  func cacheDraft(forLeadID leadID: String, draft: String) {
    cacheString(draft, forKey: leadID, category: .emailDraft)
  }
  
  func getCachedDraft(forLeadID leadID: String) -> String? {
    return getString(forKey: leadID, category: .emailDraft)
  }
  
  // MARK: - Company Data Cache
  
  func cacheCompanyInfo(domain: String, data: Data) {
    let key = domain.lowercased()
    cacheData(data, forKey: key, category: .companyData)
  }
  
  func getCachedCompanyInfo(domain: String) -> Data? {
    let key = domain.lowercased()
    return getData(forKey: key, category: .companyData)
  }
  
  // MARK: - Cache Management
  
  func clearCategory(_ category: CacheKey) {
    let prefix = category.rawValue + ":"
    stringCache = stringCache.filter { !$0.key.hasPrefix(prefix) }
    dataCache = dataCache.filter { !$0.key.hasPrefix(prefix) }
    jsonCache = jsonCache.filter { !$0.key.hasPrefix(prefix) }
    updateEntryCount()
  }
  
  func clearAll() {
    stringCache.removeAll()
    dataCache.removeAll()
    jsonCache.removeAll()
    stats = CacheStats()
  }
  
  func purgeExpired() {
    var evicted = 0
    
    for (key, entry) in stringCache where entry.isExpired {
      stringCache.removeValue(forKey: key)
      evicted += 1
    }
    for (key, entry) in dataCache where entry.isExpired {
      dataCache.removeValue(forKey: key)
      evicted += 1
    }
    for (key, entry) in jsonCache where entry.isExpired {
      jsonCache.removeValue(forKey: key)
      evicted += 1
    }
    
    stats.evictions += evicted
    updateEntryCount()
  }
  
  func getStats() -> CacheStats {
    return stats
  }
  
  // MARK: - Warm Cache
  
  func warmCache(leads: [(company: String, research: String?)]) {
    for lead in leads {
      if let research = lead.research, !research.isEmpty {
        cacheResearch(forCompany: lead.company, research: research)
      }
    }
  }
  
  // MARK: - Private Helpers
  
  private func enforceLimit() {
    let totalCount = stringCache.count + dataCache.count + jsonCache.count
    guard totalCount > maxEntries else { return }
    
    // Evict oldest string cache entries first
    let sortedStrings = stringCache.sorted { $0.value.timestamp < $1.value.timestamp }
    let toRemove = totalCount - maxEntries
    for (key, _) in sortedStrings.prefix(toRemove) {
      stringCache.removeValue(forKey: key)
      stats.evictions += 1
    }
  }
  
  private func updateEntryCount() {
    stats.totalEntries = stringCache.count + dataCache.count + jsonCache.count
    stats.memoryEstimateBytes = estimateMemoryUsage()
  }
  
  private func estimateMemoryUsage() -> Int {
    var bytes = 0
    for (key, entry) in stringCache {
      bytes += key.utf8.count + entry.value.utf8.count + 24
    }
    for (key, entry) in dataCache {
      bytes += key.utf8.count + entry.value.count + 24
    }
    return bytes
  }
}

// MARK: - Cache-Aware Research Helper

extension CacheService {
  
  /// Check cache before calling Perplexity API
  func getOrFetchResearch(
    forCompany company: String,
    fetcher: (String) async throws -> String
  ) async throws -> (result: String, fromCache: Bool) {
    // Check cache first
    if let cached = getCachedResearch(forCompany: company) {
      return (cached, true)
    }
    
    // Fetch from API
    let result = try await fetcher(company)
    
    // Cache the result
    cacheResearch(forCompany: company, research: result)
    
    return (result, false)
  }
}
