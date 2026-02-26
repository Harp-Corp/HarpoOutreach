import Foundation
// MARK: - RetryService
// Wiederverwendbare Retry-Logik fuer alle Netzwerk-Operationen
// Exponential Backoff mit konfigurierbaren Parametern
enum RetryError: LocalizedError {
    case maxRetriesExceeded(lastError: Error)
    case rateLimited(retryAfter: TimeInterval)
    case nonRetryable(Error)
    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded(let err):
            return "Max retries exceeded. Last error: \(err.localizedDescription)"
        case .rateLimited(let after):
            return "Rate limited. Retry after \(Int(after))s"
        case .nonRetryable(let err):
            return "Non-retryable error: \(err.localizedDescription)"
        }
    }
}
struct RetryConfig {
    var maxRetries: Int = 3
    var baseDelay: TimeInterval = 1.0
    var maxDelay: TimeInterval = 30.0
    var backoffMultiplier: Double = 2.0
    var retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    var nonRetryableStatusCodes: Set<Int> = [400, 401, 403, 404]
    static let `default` = RetryConfig()
    static let aggressive = RetryConfig(maxRetries: 5, baseDelay: 0.5, maxDelay: 60.0)
    static let gentle = RetryConfig(maxRetries: 2, baseDelay: 2.0, maxDelay: 15.0)
}
class RetryService {
    // MARK: - Generic Retry mit async/await
    static func withRetry<T>(
        config: RetryConfig = .default,
        operation: String = "operation",
        task: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0...config.maxRetries {
            do {
                let result = try await task()
                if attempt > 0 {
                    print("[Retry] \(operation) succeeded after \(attempt) retries")
                }
                return result
            } catch {
                lastError = error
                // Pruefe ob Fehler retryable ist
                if isNonRetryable(error, config: config) {
                    print("[Retry] \(operation) non-retryable error: \(error.localizedDescription)")
                    throw RetryError.nonRetryable(error)
                }
                if attempt < config.maxRetries {
                    let delay = calculateDelay(attempt: attempt, config: config, error: error)
                    print("[Retry] \(operation) attempt \(attempt + 1)/\(config.maxRetries) failed. Retrying in \(String(format: "%.1f", delay))s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw RetryError.maxRetriesExceeded(lastError: lastError ?? NSError(domain: "RetryService", code: -1))
    }
    // MARK: - HTTP URLRequest mit Retry
    static func fetchWithRetry(
        request: URLRequest,
        config: RetryConfig = .default,
        operation: String = "HTTP request"
    ) async throws -> (Data, HTTPURLResponse) {
        return try await withRetry(config: config, operation: operation) {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "RetryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
            }
            // Rate Limit: spezielle Behandlung
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) } ?? 5.0
                throw RetryError.rateLimited(retryAfter: retryAfter)
            }
            // Retryable Server-Fehler
            if config.retryableStatusCodes.contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "HTTP", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(body.prefix(200)))"])
            }
            // Non-retryable Client-Fehler
            if config.nonRetryableStatusCodes.contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw RetryError.nonRetryable(
                    NSError(domain: "HTTP", code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(String(body.prefix(200)))"])
                )
            }
            return (data, http)
        }
    }
    // MARK: - Delay Berechnung (Exponential Backoff + Jitter)
    private static func calculateDelay(attempt: Int, config: RetryConfig, error: Error) -> TimeInterval {
        // Bei Rate Limit: verwende Retry-After Header wenn vorhanden
        if case RetryError.rateLimited(let retryAfter) = error {
            return min(retryAfter, config.maxDelay)
        }
        // Exponential backoff mit Jitter
        let exponential = config.baseDelay * pow(config.backoffMultiplier, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return min(exponential + jitter, config.maxDelay)
    }
    // MARK: - Non-Retryable Check
    private static func isNonRetryable(_ error: Error, config: RetryConfig) -> Bool {
        if case RetryError.nonRetryable = error { return true }
        // Fix: 'any Error' to 'NSError' cast always succeeds, use direct cast
        let nsError = error as NSError
        if nsError.domain == "HTTP" {
            return config.nonRetryableStatusCodes.contains(nsError.code)
        }
        // URLError: bestimmte sind nicht retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled, .userAuthenticationRequired, .appTransportSecurityRequiresSecureConnection:
                return true
            default:
                return false
            }
        }
        return false
    }
}
// MARK: - Convenience Extensions fuer bestehende Services
extension RetryService {
    // Perplexity API Call mit Retry
    static func callPerplexityWithRetry(
        request: URLRequest,
        operation: String = "Perplexity API"
    ) async throws -> (Data, HTTPURLResponse) {
        let config = RetryConfig(
            maxRetries: 3,
            baseDelay: 2.0,
            maxDelay: 30.0,
            retryableStatusCodes: [429, 500, 502, 503, 504],
            nonRetryableStatusCodes: [400, 401, 403]
        )
        return try await fetchWithRetry(request: request, config: config, operation: operation)
    }
    // Gmail API Call mit Retry (inkl. Token-Refresh Handling)
    static func callGmailWithRetry(
        request: URLRequest,
        operation: String = "Gmail API"
    ) async throws -> (Data, HTTPURLResponse) {
        let config = RetryConfig(
            maxRetries: 2,
            baseDelay: 1.0,
            maxDelay: 10.0,
            retryableStatusCodes: [429, 500, 502, 503],
            nonRetryableStatusCodes: [400, 403, 404]
        )
        return try await fetchWithRetry(request: request, config: config, operation: operation)
    }
    // Google Sheets API Call mit Retry
    static func callSheetsWithRetry(
        request: URLRequest,
        operation: String = "Sheets API"
    ) async throws -> (Data, HTTPURLResponse) {
        let config = RetryConfig(
            maxRetries: 3,
            baseDelay: 1.5,
            maxDelay: 20.0,
            retryableStatusCodes: [429, 500, 502, 503],
            nonRetryableStatusCodes: [400, 401, 403, 404]
        )
        return try await fetchWithRetry(request: request, config: config, operation: operation)
    }
}
