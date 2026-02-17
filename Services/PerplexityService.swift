import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar"

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
        guard let http = response as? HTTPURLResponse else { throw PplxError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PplxError.apiError(code: http.statusCode, message: String(body.prefix(300)))
        }
        let apiResp = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        guard let content = apiResp.choices?[0].message?.content else { throw PplxError.noContent }
        return content
    }

    // MARK: - 1) Unternehmen finden
    func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
        let system = "You find real companies. Return ONLY a JSON array of objects with fields: name, industry, region, website, linkedInURL, description, size, country. No markdown, no explanation."
        let user = "Find 8-10 real \(industry.rawValue) companies in \(region.countries) meeting: revenue >50M EUR, 200+ employees. Include website and LinkedIn."
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        return parseJSON(content).map { d in
            Company(name: d["name"] ?? "Unknown", industry: d["industry"] ?? industry.rawValue, region: d["region"] ?? region.rawValue, website: d["website"] ?? "", linkedInURL: d["linkedInURL"] ?? "", description: d["description"] ?? "")
        }
    }

    // MARK: - 2) Compliance-Ansprechpartner mit Cross-Referenzierung
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        // Schritt 1: Initiale Suche - strenge Anweisungen gegen Halluzination
        let system1 = """
        You are a B2B research assistant. Your task is to find REAL compliance professionals.
        CRITICAL RULES:
        - ONLY return people you can verify from public sources (LinkedIn, company website, press, regulatory filings)
        - If you cannot find verifiable contacts, return an EMPTY JSON array []
        - NEVER invent or guess names, titles, or emails
        - Each person MUST have at least a verifiable LinkedIn profile OR appear on the company website
        - Include a "source" field describing WHERE you found this person
        Return ONLY a JSON array with fields: name, title, email, linkedInURL, responsibility, source
        """
        let user1 = """
        Find compliance officers at \(company.name) (\(company.industry), \(company.region)).
        Website: \(company.website)
        Search LinkedIn, the company website \(company.website)/about, \(company.website)/team,
        press releases, and regulatory filings.
        Look for: Chief Compliance Officer, Head of Compliance, VP Regulatory Affairs,
        Data Protection Officer, General Counsel.
        ONLY return people you can verify. Empty array if none found.
        """
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey)
        let candidates = parseJSON(content1)
        if candidates.isEmpty { return [] }

        // Schritt 2: Cross-Referenzierung - jeden Kandidaten einzeln verifizieren
        var verified: [Lead] = []
        for candidate in candidates {
            let name = candidate["name"] ?? ""
            let title = candidate["title"] ?? ""
            if name.isEmpty || name == "Unknown" { continue }

            let system2 = """
            You verify if a specific person works at a specific company.
            Search LinkedIn, company website, press releases, news articles, conference speakers.
            Return ONLY a JSON object with: confirmed (true/false), name, title, linkedInURL, source.
            If you CANNOT confirm this person exists at this company, set confirmed to false.
            """
            let user2 = "Verify: Does \(name) with title \(title) currently work at \(company.name)? Search LinkedIn and \(company.website)."

            do {
                let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 1000)
                let json = cleanJSON(content2)
                guard let data = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let confirmed = dict["confirmed"] as? Bool, confirmed else {
                    continue
                }
                let verifiedName = dict["name"] as? String ?? name
                let verifiedTitle = dict["title"] as? String ?? title
                let verifiedLinkedIn = dict["linkedInURL"] as? String ?? candidate["linkedInURL"] ?? ""
                let source = dict["source"] as? String ?? candidate["source"] ?? "Perplexity cross-referenced"

                verified.append(Lead(
                    name: verifiedName,
                    title: verifiedTitle,
                    company: company.name,
                    email: candidate["email"] ?? "",
                    emailVerified: false,
                    linkedInURL: verifiedLinkedIn,
                    responsibility: candidate["responsibility"] ?? "",
                    status: .identified,
                    source: source
                ))
            } catch {
                continue
            }
        }
        return verified
    }

    // MARK: - 3) Email verifizieren
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        let system = """
        You verify business email addresses using public sources:
        - Company websites, contact/impressum pages
        - LinkedIn profiles
        - Press releases, news articles
        - Business directories (Bloomberg, Reuters, Crunchbase)
        Return ONLY a JSON object with: email, verified (boolean), notes.
        NEVER guess emails based on patterns. Only confirm what you find in sources.
        """
        let user = "Verify email for: \(lead.name), \(lead.title) at \(lead.company). Current email: \(lead.email). LinkedIn: \(lead.linkedInURL)"
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (email: lead.email, verified: false, notes: "Parse error")
        }
        return (email: dict["email"] as? String ?? lead.email, verified: dict["verified"] as? Bool ?? false, notes: dict["notes"] as? String ?? "")
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
        Name: \(lead.name), Title: \(lead.title), Company: \(lead.company)
        Their challenges: \(challenges)
        Our solution: Automated compliance monitoring, regulatory change tracking, risk assessment.
        Keep it under 150 words, personal, value-focused. No hard sell. Return JSON with: subject, body
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Compliance Solutions", body: content)
        }
        return OutboundEmail(subject: dict["subject"] as? String ?? "Compliance Solutions for \(lead.company)", body: dict["body"] as? String ?? content)
    }

    // MARK: - 6) Follow-up Email erstellen
    func draftFollowUp(lead: Lead, originalEmail: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write professional follow-up emails. Keep it brief and add new value. Return ONLY JSON with subject and body."
        let user = "Follow-up for \(lead.name) at \(lead.company). Original subject was about compliance. Under 100 words. Return JSON: subject, body"
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Following up", body: content)
        }
        return OutboundEmail(subject: dict["subject"] as? String ?? "Following up - \(lead.company)", body: dict["body"] as? String ?? content)
    }

    // MARK: - JSON Helpers
    private func cleanJSON(_ content: String) -> String {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("[") || s.hasPrefix("{") { return s }
        if let a = s.firstIndex(of: "["), let b = s.lastIndex(of: "]") { return String(s[a...b]) }
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { return String(s[a...b]) }
        return s
    }

    private func parseJSON(_ content: String) -> [[String: String]] {
        let cleaned = cleanJSON(content)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        do {
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return array.map { dict in
                    var result: [String: String] = [:]
                    for (key, value) in dict { result[key] = "\(value)" }
                    return result
                }
            }
        } catch {}
        return []
    }
}

// MARK: - API Strukturen
struct PerplexityRequest: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let web_search_options: WebSearchOptions
    struct Message: Codable { let role: String; let content: String }
    struct WebSearchOptions: Codable { let search_context_size: String }
}

struct PerplexityResponse: Codable {
    let choices: [Choice]?
    struct Choice: Codable { let message: Message? }
    struct Message: Codable { let content: String? }
}

enum PplxError: LocalizedError {
    case invalidResponse
    case apiError(code: Int, message: String)
    case noContent
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response"
        case .apiError(let code, let msg): return "API Error \(code): \(msg)"
        case .noContent: return "No content"
        }
    }
}
