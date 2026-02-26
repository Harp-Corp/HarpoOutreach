import Foundation

// MARK: - RateLimiter
// Verbesserung 11: Rate-Limiting fuer alle API-Calls
// Verhindert API-Throttling und Gmail-Send-Limits
actor RateLimiter {
    
    // MARK: - Configuration per service
    private var limits: [String: ServiceLimit] = [
        "perplexity": ServiceLimit(maxRequests: 20, windowSeconds: 60),
        "gmail_send": ServiceLimit(maxRequests: 10, windowSeconds: 60),
        "gmail_read": ServiceLimit(maxRequests: 30, windowSeconds: 60),
        "sheets": ServiceLimit(maxRequests: 20, windowSeconds: 60)
    ]
    
    // MARK: - Request tracking
    private var requestLog: [String: [Date]] = [:]
    
    // MARK: - Singleton
    static let shared = RateLimiter()
    
    // MARK: - Check and wait if needed
    func acquire(service: String) async throws {
        guard let limit = limits[service] else { return }
        
        // Clean old entries
        let cutoff = Date().addingTimeInterval(-limit.windowSeconds)
        var log = requestLog[service] ?? []
        log.removeAll { $0 < cutoff }
        
        // Check if at limit
        if log.count >= limit.maxRequests {
            // Calculate wait time until oldest entry expires
            if let oldest = log.first {
                let waitTime = oldest.timeIntervalSinceNow + limit.windowSeconds
                if waitTime > 0 {
                    print("[RateLimiter] \(service): limit reached, waiting \(Int(waitTime))s")
                    try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
            }
            // Re-clean after wait
            let newCutoff = Date().addingTimeInterval(-limit.windowSeconds)
            log.removeAll { $0 < newCutoff }
        }
        
        // Record request
        log.append(Date())
        requestLog[service] = log
    }
    
    // MARK: - Remaining requests
    func remaining(service: String) -> Int {
        guard let limit = limits[service] else { return Int.max }
        let cutoff = Date().addingTimeInterval(-limit.windowSeconds)
        let recent = (requestLog[service] ?? []).filter { $0 >= cutoff }
        return max(0, limit.maxRequests - recent.count)
    }
    
    // MARK: - Stats
    func stats() -> [String: RateLimitStats] {
        var result: [String: RateLimitStats] = [:]
        for (service, limit) in limits {
            let cutoff = Date().addingTimeInterval(-limit.windowSeconds)
            let recent = (requestLog[service] ?? []).filter { $0 >= cutoff }
            result[service] = RateLimitStats(
                service: service,
                used: recent.count,
                limit: limit.maxRequests,
                windowSeconds: limit.windowSeconds,
                remaining: max(0, limit.maxRequests - recent.count)
            )
        }
        return result
    }
    
    // MARK: - Configure custom limits
    func setLimit(service: String, maxRequests: Int, windowSeconds: TimeInterval) {
        limits[service] = ServiceLimit(maxRequests: maxRequests, windowSeconds: windowSeconds)
    }
    
    // MARK: - Reset
    func reset(service: String? = nil) {
        if let service = service {
            requestLog[service] = []
        } else {
            requestLog = [:]
        }
    }
}

// MARK: - Models
struct ServiceLimit {
    let maxRequests: Int
    let windowSeconds: TimeInterval
}

struct RateLimitStats {
    let service: String
    let used: Int
    let limit: Int
    let windowSeconds: TimeInterval
    let remaining: Int
    
    var usagePercent: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit) * 100
    }
}
