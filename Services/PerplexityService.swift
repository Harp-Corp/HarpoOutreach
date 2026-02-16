import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar"  // FIXED: Changed from "sonar-pro" to "sonar"
    
    // MARK: - Generic API Call
    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String, maxTokens: Int = 4000) async throws -> String {
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
        let system = "You find real companies. Return ONLY a JSON array of objects with fields: name, industry, region, website, linkedInURL, description, size, country. No markdown, no explanation."
        
        let user = "Find 8-10 real \(industry.rawValue) companies in \(region.countries) meeting: revenue >50M EUR, 200+ employees. Include website and LinkedIn."
        
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
                linkedInURL: d["linkedInURL"] ?? "",
                description: d["description"] ?? ""
            )
        }
        
        print("[DEBUG] Parsed companies count: \(parsed.count)")
        return parsed
    }
    
    // MARK: - 2) Compliance-Ansprechpartner finden
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        let system = "You find real compliance professionals at specific companies. Return ONLY a JSON array with: name, title, email, linkedInURL, responsibility. No markdown."
        
        let user = "Find compliance officers, Chief Compliance Officers, heads of compliance, regulatory affairs managers at \(company.name). Include their business email and LinkedIn profile."
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        
        return parseJSON(content).map { d in
            Lead(
                name: d["name"] ?? "Unknown",
                title: d["title"] ?? "",
                company: company.name,
                email: d["email"] ?? "",
                emailVerified: false,
                linkedInURL: d["linkedInURL"] ?? "",
                responsibility: d["responsibility"] ?? "",
                status: .identified,
                source: d["source"] ?? "Perplexity Sonar"
            )
        }
    }
    
    // MARK: - 3) Email verifizieren - ERWEITERT mit LinkedIn und allen Quellen
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        let system = """You are an email verification expert. Use ALL available sources including:
- Company websites and contact pages
- LinkedIn profiles  
- Business directories (Bloomberg, Reuters, Crunchbase)
- Press releases and news articles
- Industry publications
- Professional networks

Return ONLY a JSON object with: email, verified (boolean), notes.
If you find a different/better email, include it. If the email format is standard for the company domain, that increases confidence."""
        
        let user = """Verify the business email address for:
Name: \(lead.name)
Title: \(lead.title)
Company: \(lead.company)
Provided email: \(lead.email)
LinkedIn: \(lead.linkedInURL)

Search for this person across LinkedIn, company website, news, and professional directories.
Verify if \(lead.email) is likely correct or find the actual email."""
        
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
        let system = "You research specific regulatory and compliance challenges. Return a concise summary of key challenges."
        
        let user = "What are the top 3-5 regulatory compliance challenges for \(company.name) in \(company.industry)? Focus on current regulations, upcoming changes, and pain points."
        
        return try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
    }
    
    // MARK: - 5) Personalisierte Email erstellen
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write professional B2B outreach emails. Write a personalized, non-salesy email that provides value."
        
        let user = """
        Write a cold outreach email from \(senderName) at Harpocrates Corp (RegTech company) to:
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company)
        
        Their challenges: \(challenges)
        
        Our solution: Automated compliance monitoring, regulatory change tracking, risk assessment.
        
        Keep it under 150 words, personal, value-focused. No hard sell.
        Return JSON with: subject, body
        """
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Compliance Solutions", body: content)
        }
        
        return OutboundEmail(
            subject: dict["subject"] as? String ?? "Compliance Solutions for \(lead.company)",
            body: dict["body"] as? String ?? content
        )
    }
    
    // MARK: - 6) Follow-up Email erstellen
    func draftFollowUp(lead: Lead, originalEmail: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write professional follow-up emails. Keep it brief and add new value."
        
        let user = """
        Write a follow-up email from \(senderName) at Harpocrates Corp to:
        Name: \(lead.name)
        Company: \(lead.company)
        
        Original email was about compliance solutions.
        
        Keep it under 100 words. Add a new insight or offer.
        Return JSON with: subject, body
        """
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Following up", body: content)
        }
        
        return OutboundEmail(
            subject: dict["subject"] as? String ?? "Following up - \(lead.company)",
            body: dict["body"] as? String ?? content
        )
    }
    
    // MARK: - Hilfsfunktionen
    private func cleanJSON(_ content: String) -> String {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Entferne Markdown Code-Blocks
        if s.hasPrefix("```json") {
            s = String(s.dropFirst(7))
        } else if s.hasPrefix("```") {
            s = String(s.dropFirst(3))
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // WICHTIG: Direkt zurueckgeben, wenn es mit [ oder { beginnt
        if s.hasPrefix("[") || s.hasPrefix("{") {
            return s
        }
        
        // Fallback: Suche nach Array oder Object
        if let aStart = s.firstIndex(of: "["), let aEnd = s.lastIndex(of: "]") {
            return String(s[aStart...aEnd])
        }
        if let oStart = s.firstIndex(of: "{"), let oEnd = s.lastIndex(of: "}") {
            return String(s[oStart...oEnd])
        }
        
        return s
    }
    
    private func parseJSON(_ content: String) -> [[String: String]] {
        let cleaned = cleanJSON(content)
        
        guard let data = cleaned.data(using: .utf8) else {
            print("[DEBUG] Failed to convert to data")
            return []
        }
        
        do {
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return array.map { dict in
                    var result: [String: String] = [:]
                    for (key, value) in dict {
                        result[key] = "\(value)"
                    }
                    return result
                }
            }
        } catch {
            print("[DEBUG] JSON parse error: \(error)")
        }
        
        return []
    }
}

// MARK: - Perplexity API Strukturen
struct PerplexityRequest: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let web_search_options: WebSearchOptions
    
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
    }
    
    struct Message: Codable {
        let content: String?
    }
}

enum PplxError: LocalizedError {
    case invalidResponse
    case apiError(code: Int, message: String)
    case noContent
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .apiError(let code, let msg): return "API Error \(code): \(msg)"
        case .noContent: return "No content in response"
        }
    }
}
