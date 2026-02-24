// HarpoOutreachWeb - Vapor Server Entry Point
// Serves REST API + static web frontend
// Services: Perplexity, GoogleAuth, Gmail, Sheets

import Vapor
import Foundation
import HarpoOutreachCore

// MARK: - Application Storage Keys
struct AuthServiceKey: StorageKey {
  typealias Value = GoogleAuthServiceWeb
}
struct GmailServiceKey: StorageKey {
  typealias Value = GmailServiceWeb
}
struct SheetsServiceKey: StorageKey {
  typealias Value = GoogleSheetsServiceWeb
}
struct PerplexityServiceKey: StorageKey {
  typealias Value = PerplexityServiceWeb
}

extension Application {
  var authService: GoogleAuthServiceWeb? {
    get { storage[AuthServiceKey.self] }
    set { storage[AuthServiceKey.self] = newValue }
  }
  var gmailService: GmailServiceWeb? {
    get { storage[GmailServiceKey.self] }
    set { storage[GmailServiceKey.self] = newValue }
  }
  var sheetsService: GoogleSheetsServiceWeb? {
    get { storage[SheetsServiceKey.self] }
    set { storage[SheetsServiceKey.self] = newValue }
  }
  var perplexityService: PerplexityServiceWeb? {
    get { storage[PerplexityServiceKey.self] }
    set { storage[PerplexityServiceKey.self] = newValue }
  }
}

@main
struct HarpoOutreachWebApp {
  static func main() async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)
    let app = Application(env)
    defer { app.shutdown() }

    // CORS
    let cors = CORSMiddleware(configuration: .init(
      allowedOrigin: .all,
      allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
      allowedHeaders: [.accept, .authorization, .contentType, .origin]
    ))
    app.middleware.use(cors, at: .beginning)

    // Static files from Public/
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Init services
    let config = AppConfig()
    let authService = GoogleAuthServiceWeb(
      clientID: config.googleClientID,
      clientSecret: config.googleClientSecret,
      redirectURI: config.googleRedirectURI
    )
    app.authService = authService
    app.gmailService = GmailServiceWeb(authService: authService, client: app.client)
    app.sheetsService = GoogleSheetsServiceWeb(authService: authService, client: app.client)
    app.perplexityService = PerplexityServiceWeb(apiKey: config.perplexityAPIKey, client: app.client)

    // Register API routes
    try configureRoutes(app)

    try app.run()
  }
}

func configureRoutes(_ app: Application) throws {

  // Health check
  app.get("health") { req -> String in
    return "OK"
  }

  let api = app.grouped("api", "v1")

  // MARK: - Industries & Regions
  api.get("industries") { req -> Response in
    let industries = Industry.allCases.map { ind in
      ["id": ind.rawValue, "shortName": ind.shortName,
       "naceSection": ind.naceSection, "keyRegulations": ind.keyRegulations]
    }
    let data = try JSONSerialization.data(withJSONObject: industries)
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  api.get("regions") { req -> Response in
    let regions = Region.allCases.map { r in
      ["id": r.rawValue, "countries": r.countries]
    }
    let data = try JSONSerialization.data(withJSONObject: regions)
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Google OAuth Flow
  api.get("auth", "google") { req -> Response in
    guard let authService = req.application.authService else {
      throw Abort(.internalServerError, reason: "Auth service not initialized")
    }
    let url = await authService.buildAuthURL()
    return req.redirect(to: url)
  }

  api.get("auth", "callback") { req -> Response in
    guard let authService = req.application.authService else {
      throw Abort(.internalServerError, reason: "Auth service not initialized")
    }
    guard let code = req.query[String.self, at: "code"] else {
      throw Abort(.badRequest, reason: "Missing OAuth code")
    }
    try await authService.handleCallback(code: code, client: req.client)
    return req.redirect(to: "/?auth=success")
  }

  api.get("auth", "status") { req -> Response in
    guard let authService = req.application.authService else {
      throw Abort(.internalServerError)
    }
    let isAuth = await authService.isAuthenticated
    let email = await authService.currentEmail
    let result: [String: Any] = ["authenticated": isAuth, "email": email]
    let data = try JSONSerialization.data(withJSONObject: result)
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  api.post("auth", "logout") { req -> Response in
    guard let authService = req.application.authService else {
      throw Abort(.internalServerError)
    }
    await authService.logout()
    let data = try JSONEncoder().encode(APIResponse(success: true, data: "Logged out"))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Companies Search (Perplexity)
  api.post("companies", "search") { req -> Response in
    guard let perplexity = req.application.perplexityService else {
      throw Abort(.internalServerError, reason: "Perplexity service not initialized")
    }
    let searchReq = try req.content.decode(SearchCompaniesRequest.self)
    let companies = try await perplexity.searchCompanies(
      industry: searchReq.industry,
      region: searchReq.region,
      count: searchReq.count ?? 10
    )
    let data = try JSONEncoder().encode(APIResponse(success: true, data: companies))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Email Draft (Perplexity)
  api.post("email", "draft") { req -> Response in
    guard let perplexity = req.application.perplexityService else {
      throw Abort(.internalServerError, reason: "Perplexity service not initialized")
    }
    let draftReq = try req.content.decode(DraftEmailRequest.self)
    let draft = try await perplexity.draftOutreachEmail(
      lead: draftReq.lead,
      emailType: draftReq.emailType,
      language: draftReq.language ?? "de"
    )
    let data = try JSONEncoder().encode(APIResponse(success: true, data: draft))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Email Send (Gmail)
  api.post("email", "send") { req -> Response in
    guard let gmail = req.application.gmailService else {
      throw Abort(.internalServerError, reason: "Gmail service not initialized")
    }
    let sendReq = try req.content.decode(SendEmailRequest.self)
    let messageId = try await gmail.sendEmail(
      to: sendReq.to,
      from: sendReq.from,
      subject: sendReq.subject,
      body: sendReq.body
    )
    let data = try JSONEncoder().encode(APIResponse(success: true, data: messageId))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Check Replies (Gmail)
  api.post("email", "replies") { req -> Response in
    guard let gmail = req.application.gmailService else {
      throw Abort(.internalServerError, reason: "Gmail service not initialized")
    }
    let checkReq = try req.content.decode(CheckRepliesRequest.self)
    let replies = try await gmail.checkReplies(
      sentSubjects: checkReq.sentSubjects,
      leadEmails: checkReq.leadEmails ?? []
    )
    let data = try JSONEncoder().encode(APIResponse(success: true, data: replies))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Sheets: Initialize
  api.post("sheets", "init") { req -> Response in
    guard let sheets = req.application.sheetsService else {
      throw Abort(.internalServerError, reason: "Sheets service not initialized")
    }
    let body = try req.content.decode(SheetsIDRequest.self)
    try await sheets.initializeSheet(spreadsheetID: body.spreadsheetID)
    let data = try JSONEncoder().encode(APIResponse(success: true, data: "Sheet initialized"))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Sheets: Read all leads
  api.get("sheets", "leads") { req -> Response in
    guard let sheets = req.application.sheetsService else {
      throw Abort(.internalServerError, reason: "Sheets service not initialized")
    }
    guard let sheetID = req.query[String.self, at: "sheetId"] else {
      throw Abort(.badRequest, reason: "Missing sheetId query parameter")
    }
    let rows = try await sheets.readAllLeads(spreadsheetID: sheetID)
    let data = try JSONEncoder().encode(APIResponse(success: true, data: rows))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Social Post (Perplexity)
  api.post("social", "generate") { req -> Response in
    guard let perplexity = req.application.perplexityService else {
      throw Abort(.internalServerError, reason: "Perplexity service not initialized")
    }
    let postReq = try req.content.decode(GeneratePostRequest.self)
    let post = try await perplexity.generateSocialPost(
      lead: postReq.lead,
      platform: postReq.platform
    )
    let data = try JSONEncoder().encode(APIResponse(success: true, data: post))
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }

  // MARK: - Dashboard
  api.get("dashboard") { req -> Response in
    let stats = DashboardStats()
    let data = try JSONEncoder().encode(stats)
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
  }
}

// MARK: - Request DTOs (Vapor Codable)
extension SearchCompaniesRequest: Content {}
extension DraftEmailRequest: Content {}
extension SendEmailRequest: Content {}
extension GeneratePostRequest: Content {}

struct CheckRepliesRequest: Content {
  let sentSubjects: [String]
  let leadEmails: [String]?
}

struct SheetsIDRequest: Content {
  let spreadsheetID: String
}
