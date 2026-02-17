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
    
    // MARK: - 2) Compliance-Ansprechpartner mit Multi-Source Cross-Referenzierung
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        // Schritt 1: LinkedIn-fokussierte Suche
        let systemLinkedIn = """
        You are a research assistant searching LinkedIn for compliance professionals.
        ABSOLUTE RULES:
        - ONLY return people with REAL LinkedIn profiles you found in search results
        - Each person MUST have a linkedin.com/in/ URL that you actually found
        - If you find NO verifiable LinkedIn profiles, return an EMPTY JSON array []
        - NEVER invent names, titles, or LinkedIn URLs
        - Do NOT guess or construct LinkedIn URLs from name patterns
        Return ONLY a JSON array with fields: name, title, linkedInURL, source
        The source field must say "LinkedIn search" and describe what you found.
        """
        let userLinkedIn = "Search LinkedIn for compliance officers at \(company.name). Look for: Chief Compliance Officer, Head of Compliance, VP Regulatory, DPO, General Counsel. ONLY return people with real LinkedIn profile URLs you found. Empty array [] if none found."
        
        let content1 = try await callAPI(systemPrompt: systemLinkedIn, userPrompt: userLinkedIn, apiKey: apiKey)
        let linkedInResults = parseJSON(content1)
        
        // Schritt 2: Unternehmenswebsite-fokussierte Suche
        let systemWebsite = """
        You are a research assistant searching company websites for compliance team members.
        ABSOLUTE RULES:
        - ONLY return people you found on the company website (team page, about page, impressum, press releases)
        - Each person MUST have a sourceURL pointing to the actual page where you found them
        - If you find NO verifiable people on the website, return an EMPTY JSON array []
        - NEVER invent names or titles
        Return ONLY a JSON array with fields: name, title, sourceURL, source
        The source field must describe the exact page where you found this person.
        """
        let userWebsite = "Search \(company.website) for compliance team members. Check /about, /team, /leadership, /impressum, /management, /kontakt pages. Look for compliance officers, regulatory affairs, data protection officers. ONLY return people actually listed on the website. Empty array [] if none found."
        
        let content2 = try await callAPI(systemPrompt: systemWebsite, userPrompt: userWebsite, apiKey: apiKey)
        let websiteResults = parseJSON(content2)
        
        // Schritt 3: Presse und Regulierungsdatenbank-Suche
        let systemPress = """
        You search press releases, news articles, regulatory filings, and conference speaker lists.
        ABSOLUTE RULES:
        - ONLY return people mentioned in actual press releases, news, or regulatory documents
        - Each person MUST have a sourceURL pointing to the article/document where they are mentioned
        - If you find NO verifiable mentions, return an EMPTY JSON array []
        - NEVER invent names, titles, or article URLs
        Return ONLY a JSON array with fields: name, title, sourceURL, source
        The source field must describe the article or document where you found this person.
        """
        let userPress = "Search for press releases, news articles, and regulatory filings mentioning compliance officers at \(company.name) in \(company.industry). Look for people with titles like CCO, Head of Compliance, DPO. ONLY return people with verifiable source URLs. Empty array [] if none found."
        
        let content3 = try await callAPI(systemPrompt: systemPress, userPrompt: userPress, apiKey: apiKey)
        let pressResults = parseJSON(content3)
        
        // Schritt 4: Cross-Referenzierung - Kandidaten die in 2+ Quellen erscheinen
        var candidateScores: [String: (name: String, title: String, linkedInURL: String, sources: [String], score: Int)] = [:]
        
        // LinkedIn-Ergebnisse indizieren
        for r in linkedInResults {
            let name = r["name"] ?? ""
            if name.isEmpty || name == "Unknown" { continue }
            let key = normalizeName(name)
            if var existing = candidateScores[key] {
                existing.sources.append(r["source"] ?? "LinkedIn")
                existing.score += 1
                if existing.linkedInURL.isEmpty { existing.linkedInURL = r["linkedInURL"] ?? "" }
                candidateScores[key] = existing
            } else {
                candidateScores[key] = (name: name, title: r["title"] ?? "", linkedInURL: r["linkedInURL"] ?? "", sources: [r["source"] ?? "LinkedIn"], score: 1)
            }
        }
        
        // Website-Ergebnisse cross-referenzieren
        for r in websiteResults {
            let name = r["name"] ?? ""
            if name.isEmpty || name == "Unknown" { continue }
            let key = normalizeName(name)
            if var existing = candidateScores[key] {
                existing.sources.append(r["source"] ?? "Company website")
                existing.score += 1
                if existing.title.isEmpty { existing.title = r["title"] ?? "" }
                candidateScores[key] = existing
            } else {
                candidateScores[key] = (name: name, title: r["title"] ?? "", linkedInURL: "", sources: [r["source"] ?? "Company website"], score: 1)
            }
        }
        
        // Presse-Ergebnisse cross-referenzieren
        for r in pressResults {
            let name = r["name"] ?? ""
            if name.isEmpty || name == "Unknown" { continue }
            let key = normalizeName(name)
            if var existing = candidateScores[key] {
                existing.sources.append(r["source"] ?? "Press/News")
                existing.score += 1
                if existing.title.isEmpty { existing.title = r["title"] ?? "" }
                candidateScores[key] = existing
            } else {
                candidateScores[key] = (name: name, title: r["title"] ?? "", linkedInURL: "", sources: [r["source"] ?? "Press/News"], score: 1)
            }
        }
        
        // Schritt 5: Nur Kandidaten mit Score >= 2 (in mindestens 2 Quellen gefunden) behalten
        // Falls niemand Score >= 2 hat, einzelne mit starken LinkedIn-Profilen akzeptieren
        var verified: [Lead] = []
        let highConfidence = candidateScores.values.filter { $0.score >= 2 }
        let candidatesToUse = highConfidence.isEmpty ? 
            Array(candidateScores.values.filter { !$0.linkedInURL.isEmpty && $0.linkedInURL.contains("linkedin.com/in/") }.prefix(3)) :
            Array(highConfidence)
        
        for candidate in candidatesToUse {
            verified.append(Lead(
                name: candidate.name,
                title: candidate.title,
                company: company.name,
                email: "",
                emailVerified: false,
                linkedInURL: candidate.linkedInURL,
                responsibility: candidate.title,
                status: .identified,
                source: "Cross-referenziert (\(candidate.score) Quellen): \(candidate.sources.joined(separator: "; "))"
            ))
        }
        
        return verified
    }
    
    // Hilfsfunktion: Name normalisieren fuer Vergleich
    private func normalizeName(_ name: String) -> String {
        return name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "dr. ", with: "")
            .replacingOccurrences(of: "dr ", with: "")
            .replacingOccurrences(of: "prof. ", with: "")
            .replacingOccurrences(of: "prof ", with: "")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        Keep it under 150 words, personal, value-focused. No hard sell.
        Return JSON with: subject, body
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
