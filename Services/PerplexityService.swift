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
        let user = "Find 20-25 real \(industry.rawValue) companies in \(region.countries) meeting: revenue >50M EUR, 200+ employees. Include website and LinkedIn."
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        return parseJSON(content).map { d in
            Company(name: d["name"] ?? "Unknown", industry: d["industry"] ?? industry.rawValue, region: d["region"] ?? region.rawValue, website: d["website"] ?? "", linkedInURL: d["linkedInURL"] ?? "", description: d["description"] ?? "")
        }
    }
    
    // MARK: - 2) Ansprechpartner finden - Breite Suche ueber ALLE Quellen
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        // Schritt 1: Breite Suche ueber alle verfuegbaren Quellen
        let system1 = """
        You are a B2B research assistant. Search ALL available sources to find compliance and regulatory professionals at a specific company.
        
        Search these sources:
        - LinkedIn profiles and company pages
        - Company website (team, about, leadership, impressum pages)
        - Business directories (Bloomberg, Reuters, Crunchbase, ZoomInfo, Apollo)
        - Press releases and news articles
        - Regulatory filings and registrations
        - Conference speaker lists and industry events
        - Professional associations and memberships
        - XING profiles (for DACH region)
        - Annual reports and corporate governance documents
        
        Return a JSON array of objects. Each object must have these fields:
        - name: Full name of the person
        - title: Their job title
        - email: Email if found, empty string if not
        - linkedInURL: LinkedIn profile URL if found, empty string if not
        - source: Where you found this person (e.g. "LinkedIn", "Company website /team", "Press release")
        
        IMPORTANT: Return ALL people you find, even if you only found them in one source.
        Include anyone in compliance, legal, regulatory, data protection, or risk management roles.
        If you find someone but are unsure of their exact title, still include them with your best guess.
        """
        let user1 = """
        Find compliance and regulatory professionals at \(company.name) (Industry: \(company.industry), Region: \(company.region)).
        Company website: \(company.website)
        
        Search for people with roles like:
        - Chief Compliance Officer (CCO)
        - Head of Compliance
        - Compliance Manager/Director
        - VP/SVP Regulatory Affairs
        - Data Protection Officer (DPO/DSB)
        - General Counsel / Chief Legal Officer
        - Head of Risk Management
        - Head of Legal
        - Geldwaeschebeauftragter (for financial services)
        - Datenschutzbeauftragter
        
        Search LinkedIn, \(company.website), business directories, press releases, XING, annual reports.
        Return ALL people you find as JSON array.
        """
        
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
        var allCandidates = parseJSON(content1)
        
        // Schritt 2: Falls wenig Ergebnisse, zweite Suche mit anderen Suchtermen
        if allCandidates.count < 3 {
            let system2 = """
            You are a research assistant. Search the web for executives and senior managers at a specific company.
            Return a JSON array with fields: name, title, email, linkedInURL, source.
            Search LinkedIn, company websites, news, business directories, XING, and any other public source.
            Return ALL people you find. Include email if available, empty string if not.
            """
            let user2 = """
            Find senior managers and executives at \(company.name) who work in compliance, legal, regulatory, risk, or data protection.
            Also search for: Vorstand, Geschaeftsfuehrung, C-Level executives at \(company.name).
            Website: \(company.website)
            Search broadly across LinkedIn, XING, \(company.website), Google, business registers.
            Return JSON array with: name, title, email, linkedInURL, source.
            """
            
            do {
                let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 4000)
                let moreResults = parseJSON(content2)
                // Merge ohne Duplikate
                for candidate in moreResults {
                    let name = candidate["name"] ?? ""
                    if !name.isEmpty && !allCandidates.contains(where: { normalizeName($0["name"] ?? "") == normalizeName(name) }) {
                        allCandidates.append(candidate)
                    }
                }
            } catch {
                // Zweite Suche fehlgeschlagen - kein Problem, wir haben die erste
            }
        }
        
        // Schritt 3: Alle gefundenen Kandidaten als Leads zurueckgeben
        var leads: [Lead] = []
        for candidate in allCandidates {
            let name = candidate["name"] ?? ""
            if name.isEmpty || name == "Unknown" || name.count < 3 { continue }
            
            let email = candidate["email"] ?? ""
            let linkedIn = candidate["linkedInURL"] ?? ""
            let source = candidate["source"] ?? "Perplexity Search"
            let title = candidate["title"] ?? ""
            
            // Duplikat-Check
            if leads.contains(where: { normalizeName($0.name) == normalizeName(name) }) { continue }
            
            leads.append(Lead(
                name: name,
                title: title,
                company: company.name,
                email: cleanEmail(email),
                emailVerified: false,
                linkedInURL: linkedIn,
                responsibility: title,
                status: .identified,
                source: source
            ))
        }
        
        return leads
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
    
    // Hilfsfunktion: Email bereinigen
    private func cleanEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") && trimmed.contains(".") {
            return trimmed.lowercased()
        }
        return ""
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
        let rawBody = dict["body"] as? String ?? content
        return OutboundEmail(subject: dict["subject"] as? String ?? "Compliance Solutions for \(lead.company)", body: stripCitations(rawBody))
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
        let rawBody2 = dict["body"] as? String ?? content
        return OutboundEmail(subject: dict["subject"] as? String ?? "Following up - \(lead.company)", body: stripCitations(rawBody2))
    }
    
    // MARK: - JSON Helpers

    private func stripCitations(_ text: String) -> String {
        var result = text
        let pattern = "\\s*\\[\\d+(,\\s*\\d+)*\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
