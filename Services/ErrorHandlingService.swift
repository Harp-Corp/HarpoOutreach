import Foundation
import Combine

// MARK: - ErrorHandlingService
// Centralized error handling, logging, and user-facing error presentation.
// Replaces scattered error handling with a unified approach.

@MainActor
class ErrorHandlingService: ObservableObject {

  static let shared = ErrorHandlingService()

  @Published var currentError: AppError?
  @Published var showingError = false
  @Published var errorLog: [ErrorLogEntry] = []

  // MARK: - Error Handling

  /// Handle an error with context about where it occurred.
  func handle(_ error: Error, context: ErrorContext, silent: Bool = false) {
    let appError = AppError(error: error, context: context)
    log(appError)

    if !silent {
      currentError = appError
      showingError = true
    }

    #if DEBUG
    print("[ERROR] [\(context.rawValue)] \(error.localizedDescription)")
    #endif
  }

  /// Handle an error with a custom user-facing message.
  func handle(_ error: Error, context: ErrorContext, userMessage: String) {
    let appError = AppError(error: error, context: context, userMessage: userMessage)
    log(appError)
    currentError = appError
    showingError = true
  }

  /// Dismiss the current error.
  func dismiss() {
    showingError = false
    currentError = nil
  }

  // MARK: - Safe Execution

  /// Execute an async operation with automatic error handling.
  func tryAsync<T>(
    context: ErrorContext,
    silent: Bool = false,
    operation: () async throws -> T
  ) async -> T? {
    do {
      return try await operation()
    } catch {
      handle(error, context: context, silent: silent)
      return nil
    }
  }

  /// Execute an async operation with a fallback value on error.
  func tryAsync<T>(
    context: ErrorContext,
    fallback: T,
    operation: () async throws -> T
  ) async -> T {
    do {
      return try await operation()
    } catch {
      handle(error, context: context, silent: true)
      return fallback
    }
  }

  // MARK: - Error Logging

  private func log(_ appError: AppError) {
    let entry = ErrorLogEntry(
      error: appError,
      timestamp: Date()
    )
    errorLog.append(entry)

    // Keep log manageable
    if errorLog.count > 200 {
      errorLog = Array(errorLog.suffix(150))
    }
  }

  /// Clear the error log.
  func clearLog() {
    errorLog.removeAll()
  }

  // MARK: - Error Statistics

  var recentErrors: [ErrorLogEntry] {
    Array(errorLog.suffix(20).reversed())
  }

  var errorCountByContext: [ErrorContext: Int] {
    Dictionary(grouping: errorLog, by: { $0.error.context })
      .mapValues { $0.count }
  }

  var hasRecentErrors: Bool {
    guard let lastError = errorLog.last else { return false }
    return Date().timeIntervalSince(lastError.timestamp) < 300 // 5 minutes
  }

  /// Export error log as formatted string for debugging.
  func exportLog() -> String {
    let formatter = ISO8601DateFormatter()
    return errorLog.map { entry in
      "[\(formatter.string(from: entry.timestamp))] [\(entry.error.context.rawValue)] \(entry.error.localizedDescription)"
    }.joined(separator: "\n")
  }
}

// MARK: - Error Types

struct AppError: LocalizedError, Identifiable {
  let id = UUID()
  let underlyingError: Error
  let context: ErrorContext
  let userMessage: String?
  let timestamp: Date

  init(error: Error, context: ErrorContext, userMessage: String? = nil) {
    self.underlyingError = error
    self.context = context
    self.userMessage = userMessage
    self.timestamp = Date()
  }

  var errorDescription: String? {
    userMessage ?? friendlyMessage
  }

  /// Maps technical errors to user-friendly messages.
  var friendlyMessage: String {
    let desc = underlyingError.localizedDescription.lowercased()

    if desc.contains("network") || desc.contains("internet") || desc.contains("offline") {
      return "No internet connection. Please check your network and try again."
    }
    if desc.contains("timeout") || desc.contains("timed out") {
      return "The request timed out. Please try again."
    }
    if desc.contains("401") || desc.contains("unauthorized") {
      return "Authentication failed. Please check your API key."
    }
    if desc.contains("429") || desc.contains("rate limit") {
      return "Too many requests. Please wait a moment and try again."
    }
    if desc.contains("500") || desc.contains("server") {
      return "Server error. Please try again later."
    }
    if desc.contains("decode") || desc.contains("parsing") {
      return "Unexpected response format. The API response could not be processed."
    }
    return "An error occurred: \(underlyingError.localizedDescription)"
  }

  /// Severity level for the error.
  var severity: ErrorSeverity {
    let desc = underlyingError.localizedDescription.lowercased()
    if desc.contains("network") || desc.contains("timeout") { return .warning }
    if desc.contains("401") || desc.contains("unauthorized") { return .critical }
    if desc.contains("429") { return .warning }
    return .error
  }
}

enum ErrorContext: String, Codable {
  case api = "API"
  case email = "Email"
  case auth = "Authentication"
  case sheets = "Google Sheets"
  case gmail = "Gmail"
  case persistence = "Data Persistence"
  case prospecting = "Prospecting"
  case socialPost = "Social Post"
  case scheduler = "Scheduler"
  case blocklist = "Blocklist"
  case general = "General"
}

enum ErrorSeverity: String {
  case info = "Info"
  case warning = "Warning"
  case error = "Error"
  case critical = "Critical"
}

struct ErrorLogEntry: Identifiable {
  let id = UUID()
  let error: AppError
  let timestamp: Date
}
