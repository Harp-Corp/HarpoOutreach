import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar"  // FIXED: Changed from "sonar-pro" to "sonar"
    
    // MARK: - Generic API Call
    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String, maxTokens: Int = 800) async throws -> String {  // FIXED: Increased from 300 to 800
        let requestBody = PerplexityRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            max_tokens: maxTokens,
            web_search_options: .init(search_context_size: "high")
        )
        
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 90
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw PplxError.invalidResponse
        }
        
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PplxError.apiError(code: http.statusCode, message: String(body.prefix(300)))
        }
        
        let apiResp = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        
        // FIXED: Changed from .first?.message to [0].message
        guard let content = apiResp.choices?[0].message?.content else {
            throw PplxError.noContent
        }
        
        return content
    }
    
    // MARK: - 1) Unternehmen finden
    func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
        let system = "You find real companies. Return ONLY a JSON array of objects with fields: name, industry, region, website, description. No text outside the JSON. Only real, verifiable companies."
        
        let user = "Find 8-10 real \(industry.rawValue) companies in \(region.countries) that are likely to need compliance solutions. Focus on mid-size to large companies in \(industry.searchTerms). Include company website. Return ONLY valid JSON array."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        
        // DEBUG LOGGING
        print("[DEBUG] Raw response length: \(content.count)")
        print("[DEBUG] Response preview: \(String(content.prefix(200)))")
        
        let parsed = parseJSON(content).map { d in
            Company(
                name: d["name"] ?? "Unknown",
                industry: d["industry"] ?? industry.rawValue,
                region: d["region"] ?? region.rawValue,
                website: d["website"] ?? "",
                description: d["description"] ?? ""
            )
        }
        
        print("[DEBUG] Parsed companies count: \(parsed.count)")
        return parsed
    }
    
    // MARK: - 2) Compliance-Ansprechpartner finden
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        let system = "You find real compliance professionals at specific companies. Return ONLY a JSON array of objects with fields: name, title, linkedInURL, email, responsibility, source. Only real, verifiable people. If email unknown use \"\". No fake data. No text outside the JSON."
        
        let user = "Find compliance officers, Chief Compliance Officers, heads of compliance, legal/compliance directors, or managing directors responsible for compliance at \(company.name) (\(company.industry), \(company.region)). Website: \(company.website). Search LinkedIn, company website, press releases, regulatory filings. Include their LinkedIn URL if available. Return ONLY valid JSON array."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        
        return parseJSON(content).map { d in
            Lead(
                name: d["name"] ?? "Unknown",
                title: d["title"] ?? "",
                company: company,
                email: d["email"] ?? "",
                emailVerified: false,
                linkedInURL: d["linkedInURL"] ?? "",
                responsibility: d["responsibility"] ?? "",
                status: .identified,
                source: d["source"] ?? "Perplexity Sonar"
            )
        }
    }
    
    // MARK: - 3) Email verifizieren
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        let system = "You verify business email addresses. Return ONLY a JSON object with fields: email, verified (true/false), notes. Only confirm emails you can verify from public sources. Common patterns: firstname.lastname@domain, f.lastname@domain, firstname@domain. Check company website, LinkedIn, press releases, conference speakers lists, regulatory filings, XING, published articles."
        
        let user = "Find and verify the business email address for:\nName: \(lead.name)\nTitle: \(lead.title)\nCompany: \(lead.company.name)\nCompany website: \(lead.company.website)\nKnown email so far: \(lead.email)\nLinkedIn: \(lead.linkedInURL)\n\nSearch all available sources. If you cannot verify 100%, state that clearly. Return ONLY valid JSON object."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (email: lead.email, verified: false, notes: "Parse error")
        }
        
        let email = dict["email"] as? String ?? lead.email
        let verified = dict["verified"] as? Bool ?? false
        let notes = dict["notes"] as? String ?? ""
        
        return (email: email, verified: verified, notes: notes)
    }
    
    // MARK: - 4) Branchen-Challenges recherchieren
    func researchChallenges(company: Company, apiKey: String) async throws -> String {
        let system = "You are a compliance industry research expert. Write in German. Research real, current compliance challenges for the given company and industry. Return a structured text (not JSON) with:\n1. Branchenspezifische Compliance-Herausforderungen (3-4 Punkte)\n2. Unternehmensspezifische Themen (2-3 Punkte)\n3. Aktuelle regulatorische Entwicklungen\n\nBe specific, use real regulations (DORA, NIS2, CSRD, MDR, EU AI Act etc.)"
        
        let user = "Research compliance challenges for:\nCompany: \(company.name)\nIndustry: \(company.industry)\nRegion: \(company.region)\nWebsite: \(company.website)\nDescription: \(company.description)"
        
        return try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
    }
    
    // MARK: - 5) Personalisierte Email drafting
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write personalized B2B outreach emails in German for Harpocrates, a RegTech company that offers COMPLY, an AI-powered compliance management platform. COMPLY reduces compliance effort by 50% in 3 months. It monitors regulations (EU-Lex, internal), provides 360° compliance control, works across all industries, and is scalable from startups to enterprises. Website: www.harpocrates-corp.com\n\nWrite professional, warm, not pushy emails. Reference specific challenges of the recipient's industry and company. Keep it concise (max 200 words body). Return ONLY a JSON object with fields: subject, body."
        
        let user = "Draft a personalized outreach email for:\nRecipient: \(lead.name), \(lead.title)\nCompany: \(lead.company.name) (\(lead.company.industry))\nRegion: \(lead.company.region)\nChallenges:\n\(challenges)\n\nSender: \(senderName), Harpocrates Solutions GmbH\nSender email: mf@harpocrates-corp.com\n\nThe email should be in German, professional, and reference specific compliance challenges of their industry. Return ONLY JSON with subject and body."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw PplxError.parseError
        }
        
        return OutboundEmail(
            subject: dict["subject"] ?? "Compliance Automation mit Harpocrates",
            body: dict["body"] ?? ""
        )
    }

        // MARK: - 6) Follow-Up Email drafting
    func draftFollowUp(lead: Lead, originalEmail: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write personalized follow-up emails in German for Harpocrates. The follow-up should reference the original email, be brief, and maintain a professional but friendly tone. Return ONLY a JSON object with fields: subject, body."
        
        let user = "Draft a follow-up email for:\nRecipient: \(lead.name), \(lead.title)\nCompany: \(lead.company.name)\nOriginal email sent:\n\(originalEmail)\n\nSender: \(senderName), Harpocrates Solutions GmbH\nSender email: mf@harpocrates-corp.com\n\nThe follow-up should be in German, brief (max 150 words), and friendly. Return ONLY JSON with subject and body."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw PplxError.parseError
        }
        
        return OutboundEmail(
            subject: dict["subject"] ?? "Follow-Up: Compliance Automation",
            body: dict["body"] ?? ""
        )
    }
    
    // MARK: - JSON Helpers
    private func parseJSON(_ content: String) -> [[String: String]] {
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([[String: String]].self, from: data)
        } catch {
            print("JSON Parse Error: \(error)")
            print("JSON (first 300 chars): \(String(json.prefix(300)))")
            return []
        }
    }
    
    // FIXED: Improved cleanJSON function
    private func cleanJSON(_ content: String) -> String {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove Markdown code blocks
        if s.hasPrefix("```json") {
            s = String(s.dropFirst(7))
        } else if s.hasPrefix("```") {
            s = String(s.dropFirst(3))
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // IMPORTANT: Return directly if it starts with [ or {
        if s.hasPrefix("[") || s.hasPrefix("{") {
            return s
        }
        
        // Fallback: Search for array or object boundaries
        if let aStart = s.firstIndex(of: "["), let aEnd = s.lastIndex(of: "]") {
            return String(s[aStart...aEnd])
        }
        if let oStart = s.firstIndex(of: "{"), let oEnd = s.lastIndex(of: "}") {
            return String(s[oStart...oEnd])
        }
        
        return s
    }
}

// MARK: - Errors
enum PplxError: LocalizedError {
    case invalidResponse
    case apiError(code: Int, message: String)
    case noContent
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungueltige Server-Antwort"
        case .apiError(let c, let m):
            return "API Fehler \(c): \(m)"
        case .noContent:
            return "Keine Inhalte in der Antwort"
        case .parseError:
            return "JSON konnte nicht geparst werden"
        }
    }
}

// MARK: - Request/Response Structures
struct PerplexityRequest: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let web_search_options: WebSearchOptions?
    
    struct Message: Codable {
        let role: String
        let content: String
    }
    
    struct WebSearchOptions: Codable {
        let search_context_size: String
    }
}

struct PerplexityResponse: Codable {
    let choices: [Choice]?
    
    struct Choice: Codable {
        let message: Message?
        
        struct Message: Codable {
            let content: String?
        }
    }
}
