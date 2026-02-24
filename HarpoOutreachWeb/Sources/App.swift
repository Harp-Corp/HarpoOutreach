// HarpoOutreachWeb - Vapor Server Entry Point
// Serves REST API + static web frontend

import Vapor
import HarpoOutreachCore

@main
struct HarpoOutreachWebApp {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }

        // CORS for local development
        let cors = CORSMiddleware(configuration: .init(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .authorization, .contentType, .origin]
        ))
        app.middleware.use(cors, at: .beginning)

        // Serve static files from Public/
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

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

    // API v1 group
    let api = app.grouped("api", "v1")

    // --- Industries ---
    api.get("industries") { req -> Response in
        let industries = Industry.allCases.map { ind in
            ["id": ind.rawValue, "shortName": ind.shortName,
             "naceSection": ind.naceSection, "keyRegulations": ind.keyRegulations]
        }
        let data = try JSONSerialization.data(withJSONObject: industries)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Regions ---
    api.get("regions") { req -> Response in
        let regions = Region.allCases.map { r in
            ["id": r.rawValue, "countries": r.countries]
        }
        let data = try JSONSerialization.data(withJSONObject: regions)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Leads CRUD ---
    api.get("leads") { req -> Response in
        // TODO: Connect to data store (Google Sheets or DB)
        let empty: [LeadDTO] = []
        let data = try JSONEncoder().encode(empty)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    api.post("leads") { req -> Response in
        let lead = try req.content.decode(LeadDTO.self)
        let data = try JSONEncoder().encode(APIResponse(success: true, data: lead))
        return Response(status: .created, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Companies Search ---
    api.post("companies", "search") { req -> Response in
        let searchReq = try req.content.decode(SearchCompaniesRequest.self)
        // TODO: Call PerplexityService server-side
        let empty: [CompanyDTO] = []
        let data = try JSONEncoder().encode(APIResponse(success: true, data: empty))
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Email Draft ---
    api.post("email", "draft") { req -> Response in
        let draftReq = try req.content.decode(DraftEmailRequest.self)
        // TODO: Call PerplexityService server-side
        let placeholder = EmailDraftDTO(leadId: draftReq.leadId, leadName: "", leadEmail: "",
                                         companyName: "", subject: "Draft", body: "Placeholder")
        let data = try JSONEncoder().encode(APIResponse(success: true, data: placeholder))
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Email Send ---
    api.post("email", "send") { req -> Response in
        let sendReq = try req.content.decode(SendEmailRequest.self)
        // TODO: Call GmailService server-side (with server-held OAuth tokens)
        let resp = APIResponse<String>(success: true, data: "Email queued for \(sendReq.leadId)")
        let data = try JSONEncoder().encode(resp)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Social Post ---
    api.post("social", "generate") { req -> Response in
        let postReq = try req.content.decode(GeneratePostRequest.self)
        // TODO: Call PerplexityService server-side
        let placeholder = SocialPostDTO(platform: postReq.platform, content: "Generated post placeholder")
        let data = try JSONEncoder().encode(APIResponse(success: true, data: placeholder))
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Dashboard ---
    api.get("dashboard") { req -> Response in
        // TODO: Aggregate from data store
        let stats = DashboardStats()
        let data = try JSONEncoder().encode(stats)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
    }

    // --- Google OAuth (server-side) ---
    api.get("auth", "google") { req -> Response in
        // TODO: Redirect to Google OAuth consent screen
        return Response(status: .ok, body: .init(string: "OAuth flow placeholder"))
    }

    api.get("auth", "callback") { req -> Response in
        // TODO: Handle OAuth callback, store tokens server-side
        return Response(status: .ok, body: .init(string: "OAuth callback placeholder"))
    }
}
