// HarpoOutreachWeb - Server Configuration
// Reads all secrets from environment variables
import Foundation
import Vapor

struct AppConfig {
    let perplexityAPIKey: String
    let googleClientID: String
    let googleClientSecret: String
    let spreadsheetID: String
    let senderEmail: String
    let senderName: String
    let serverBaseURL: String

    /// Load from environment, crash early if critical keys missing
    static func load(from app: Application) -> AppConfig {
        let env = app.environment
        return AppConfig(
            perplexityAPIKey: Environment.get("PERPLEXITY_API_KEY") ?? "",
            googleClientID: Environment.get("GOOGLE_CLIENT_ID") ?? "",
            googleClientSecret: Environment.get("GOOGLE_CLIENT_SECRET") ?? "",
            spreadsheetID: Environment.get("GOOGLE_SPREADSHEET_ID") ?? "",
            senderEmail: Environment.get("SENDER_EMAIL") ?? "mf@harpocrates-corp.com",
            senderName: Environment.get("SENDER_NAME") ?? "Martin Foerster",
            serverBaseURL: Environment.get("SERVER_BASE_URL") ?? "http://localhost:8080"
        )
    }

    func validate(logger: Logger) {
        if perplexityAPIKey.isEmpty { logger.warning("PERPLEXITY_API_KEY not set - company search and AI features disabled") }
        if googleClientID.isEmpty { logger.warning("GOOGLE_CLIENT_ID not set - Google OAuth disabled") }
        if googleClientSecret.isEmpty { logger.warning("GOOGLE_CLIENT_SECRET not set - Google OAuth disabled") }
        if spreadsheetID.isEmpty { logger.warning("GOOGLE_SPREADSHEET_ID not set - Sheets tracking disabled") }
    }

    var isPerplexityConfigured: Bool { !perplexityAPIKey.isEmpty }
    var isGoogleConfigured: Bool { !googleClientID.isEmpty && !googleClientSecret.isEmpty }
    var isSheetsConfigured: Bool { !spreadsheetID.isEmpty && isGoogleConfigured }
}
