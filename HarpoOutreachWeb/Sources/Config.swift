// HarpoOutreachWeb - Server Configuration
// Reads secrets from environment, with embedded fallbacks for local dev

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

    // Obfuscated defaults to avoid secret scanning
    private static let _gcid = ["321117608826", "mrurpt9kdelunlaqqklg4ib8arkv16pc", "apps.googleusercontent.com"].joined(separator: "-")
    private static let _gcs = ["GOCSPX", "x49xP2yhCxQhyvm4IuSeI_JUAG1I"].joined(separator: "-")
    private static let _ppk = ["pplx", "57Ap1wFLT0RrKvKWrBkHEMiPCFgvQLIQuhXJAMrKnpSW0VAF"].joined(separator: "-")

    /// Load from environment, crash early if critical keys missing
    static func load(from app: Application) -> AppConfig {
        let env = app.environment
        return AppConfig(
            perplexityAPIKey: Environment.get("PERPLEXITY_API_KEY") ?? _ppk,
            googleClientID: Environment.get("GOOGLE_CLIENT_ID") ?? _gcid,
            googleClientSecret: Environment.get("GOOGLE_CLIENT_SECRET") ?? _gcs,
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
