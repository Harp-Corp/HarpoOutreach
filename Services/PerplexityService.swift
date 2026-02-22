import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar-pro"

    // MARK: - Generic API Call
    private func callAPI(systemPrompt: String, userPrompt: String, apiKey: String, maxTokens: Int = 4000) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PplxError.apiError(code: 401, message: "Perplexity API Key fehlt. Bitte in Einstellungen eintragen.")
        }
        print("[Perplexity] API Call mit Key: \(apiKey.prefix(8))...")
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
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PplxError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 {
                throw PplxError.apiError(code: 401, message: "Perplexity API Key ungueltig oder abgelaufen. Bitte in Einstellungen pruefen. Key beginnt mit: \(apiKey.prefix(8))...")
            }
            throw PplxError.apiError(code: http.statusCode, message: String(body.prefix(300)))
        }
        let apiResp = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        guard let content = apiResp.choices?[0].message?.content else { throw PplxError.noContent }
        return content
    }

    // MARK: - 1) Unternehmen finden
    func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
        let system = """
        You are a B2B company research assistant. You MUST return EXACTLY 25 real companies as a JSON array.
        Each object in the array MUST have these fields: name, industry, region, website, linkedInURL, description, size, country.
        CRITICAL RULES:
        - Return ONLY a valid JSON array. No markdown, no explanation, no text before or after.
        - You MUST return exactly 25 companies. Count them. Do NOT stop at 10 or 15.
        - All companies must be REAL, currently operating companies.
        - Include the full website URL (https://...) and LinkedIn company page URL.
        - If you cannot find 25, return as many as possible but aim for 25.
        """
        let user = """
        Find exactly 25 real \(industry.rawValue) companies in \(region.countries).
        Requirements:
        - Revenue > 50M EUR or equivalent
        - 200+ employees
        - Currently active and operating
        - Include company website URL and LinkedIn company page URL
        Return ALL 25 companies as a single JSON array. Do not truncate. Do not stop early.
        Count your results before returning - there must be 25 objects in the array.
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 8000)
        return parseJSON(content).map { d in
            Company(name: d["name"] ?? "Unknown", industry: d["industry"] ?? industry.rawValue,
                    region: d["region"] ?? region.rawValue, website: d["website"] ?? "",
                    linkedInURL: d["linkedInURL"] ?? "", description: d["description"] ?? "")
        }
    }

    // MARK: - 2) Ansprechpartner finden
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        let system1 = """
        You are a B2B research assistant. Search ALL available sources to find compliance and regulatory professionals at a specific company.
        Return a JSON array of objects with fields: name, title, email, linkedInURL, source.
        Include anyone in compliance, legal, regulatory, data protection, or risk management roles.
        """
        let user1 = """
        Find compliance and regulatory professionals at \(company.name) (Industry: \(company.industry), Region: \(company.region)).
        Company website: \(company.website)
        Search for: CCO, Head of Compliance, Compliance Manager/Director, DPO, General Counsel, Head of Risk, Geldwaeschebeauftragter.
        Search LinkedIn, \(company.website), theorg.com, XING, business directories, press releases, annual reports.
        Return ALL people you find as JSON array.
        """
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
        var allCandidates = parseJSON(content1)
        if allCandidates.count < 3 {
            let system2 = "You are a research assistant. Search the web for executives and senior managers at a specific company. Return a JSON array with fields: name, title, email, linkedInURL, source."
            let user2 = "Find senior managers at \(company.name) in compliance, legal, regulatory, risk, or data protection. Website: \(company.website). Return JSON array."
            if let more = try? await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 4000) {
                let moreResults = parseJSON(more)
                for candidate in moreResults {
                    let name = candidate["name"] ?? ""
                    if !name.isEmpty && !allCandidates.contains(where: { normalizeName($0["name"] ?? "") == normalizeName(name) }) {
                        allCandidates.append(candidate)
                    }
                }
            }
        }
        var leads: [Lead] = []
        for candidate in allCandidates {
            let name = candidate["name"] ?? ""
            if name.isEmpty || name == "Unknown" || name.count < 3 { continue }
            if leads.contains(where: { normalizeName($0.name) == normalizeName(name) }) { continue }
            leads.append(Lead(name: name, title: candidate["title"] ?? "", company: company.name,
                              email: cleanEmail(candidate["email"] ?? ""), emailVerified: false,
                              linkedInURL: candidate["linkedInURL"] ?? "",
                              responsibility: candidate["title"] ?? "", status: .identified,
                              source: candidate["source"] ?? "Perplexity Search"))
        }
        return leads
    }

    private func normalizeName(_ name: String) -> String {
        return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "dr. ", with: "").replacingOccurrences(of: "dr ", with: "")
            .replacingOccurrences(of: "prof. ", with: "").replacingOccurrences(of: "prof ", with: "")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func cleanEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") && trimmed.contains(".") { return trimmed.lowercased() }
        return ""
    }

    // MARK: - 3) Email verifizieren
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        var allEmails: [(email: String, source: String, confidence: String)] = []
        var allNotes: [String] = []
        let system1 = """
        You are an expert at finding verified business email addresses from public sources.
        Search exhaustively: LinkedIn, company website, theorg.com, XING, ZoomInfo, Apollo.io, Hunter.io, press releases, Handelsregister.
        Return JSON: { emails: [{email, source, confidence}], company_email_pattern: string, notes: string }
        Confidence: high = found in verified source, medium = constructed from pattern, low = guess.
        """
        let user1 = """
        Find email for: \(lead.name), \(lead.title) at \(lead.company). LinkedIn: \(lead.linkedInURL)
        Search theorg.com, LinkedIn, XING, company website, ZoomInfo, Apollo.io, Hunter.io, press releases.
        Return JSON with emails array.
        """
        if let content1 = try? await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000) {
            let json1 = cleanJSON(content1)
            if let data = json1.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let emails = dict["emails"] as? [[String: Any]] {
                    for e in emails {
                        if let addr = e["email"] as? String, !addr.isEmpty, addr.contains("@") {
                            allEmails.append((email: addr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                                              source: e["source"] as? String ?? "Search",
                                              confidence: e["confidence"] as? String ?? "medium"))
                        }
                    }
                }
                if let notes = dict["notes"] as? String, !notes.isEmpty { allNotes.append(notes) }
            }
        }
        let system2 = "You are an email verification specialist. Verify email addresses for a business contact. Return JSON: { best_email, verified, confidence, reasoning }"
        let candidateEmails = allEmails.map { $0.email }.prefix(5).joined(separator: ", ")
        let user2 = "Verify best email for \(lead.name) at \(lead.company). Candidates: \(candidateEmails.isEmpty ? "none" : candidateEmails). Return JSON."
        if let content2 = try? await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 3000) {
            let json2 = cleanJSON(content2)
            if let data = json2.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let bestEmail = dict["best_email"] as? String, !bestEmail.isEmpty, bestEmail.contains("@") {
                    let conf = dict["confidence"] as? String ?? "medium"
                    let verified = dict["verified"] as? Bool ?? false
                    allEmails.insert((email: bestEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                                      source: "Cross-verification", confidence: verified ? "high" : conf), at: 0)
                }
                if let reasoning = dict["reasoning"] as? String, !reasoning.isEmpty { allNotes.append(reasoning) }
            }
        }
        let uniqueEmails = Dictionary(grouping: allEmails, by: { $0.email })
        let best = allEmails.first(where: { $0.confidence == "high" })
            ?? allEmails.first(where: { $0.confidence == "medium" && (uniqueEmails[$0.email]?.count ?? 0) > 1 })
            ?? allEmails.first(where: { $0.confidence == "medium" })
            ?? allEmails.first
        let finalEmail = best?.email ?? lead.email
        let isVerified = best?.confidence == "high" || (best != nil && (uniqueEmails[best!.email]?.count ?? 0) > 1) || best?.confidence == "medium"
        let notes = ([best.map { "Best: \($0.email) (\($0.source), \($0.confidence))" } ?? "No email found",
                      "Total: \(allEmails.count)"] + allNotes).joined(separator: " | ")
        return (email: cleanEmail(finalEmail.isEmpty ? lead.email : finalEmail),
                verified: isVerified, notes: String(notes.prefix(500)))
    }

    // MARK: - 4) Branchen-Challenges
    func researchChallenges(company: Company, apiKey: String) async throws -> String {
        let system = "You research specific regulatory and compliance challenges. Return a concise summary."
        let user = "Top 3-5 regulatory compliance challenges for \(company.name) in \(company.industry)? Focus on current EU regulations, upcoming changes, and pain points."
        return try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
    }

    // MARK: - 5) Email erstellen
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write professional B2B outreach emails. Write a personalized, non-salesy email that provides value."
        let user = "Write cold outreach from \(senderName) at Harpocrates Solutions GmbH (RegTech) to \(lead.name), \(lead.title) at \(lead.company). Challenges: \(challenges). Under 150 words. Return JSON: {subject, body}"
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Compliance Solutions", body: content)
        }
        return OutboundEmail(subject: dict["subject"] as? String ?? "Compliance Solutions for \(lead.company)",
                             body: stripCitations(dict["body"] as? String ?? content))
    }

    // MARK: - 6) Follow-up Email
    func draftFollowUp(lead: Lead, originalEmail: String, followUpEmail: String = "", replyReceived: String = "", senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = "You write professional follow-up emails for B2B outreach. Reference previous conversation. Under 150 words. Return ONLY valid JSON: {subject, body}"
        var ctx = "Previous email to \(lead.name) at \(lead.company):\n\(originalEmail)"
        if !followUpEmail.isEmpty { ctx += "\n\nPrevious follow-up:\n\(followUpEmail)" }
        if !replyReceived.isEmpty { ctx += "\n\nReply received:\n\(replyReceived)" }
        let user = "Write follow-up from \(senderName) at Harpocrates Solutions GmbH. HISTORY:\n\(ctx)\nReturn JSON: {subject, body}"
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Following up - \(lead.company)", body: content)
        }
        return OutboundEmail(subject: dict["subject"] as? String ?? "Following up - \(lead.company)",
                             body: stripCitations(dict["body"] as? String ?? content))
    }

    // MARK: - 7) Newsletter Content generieren
    func generateNewsletterContent(topic: ContentTopic, industries: [String], apiKey: String) async throws -> (subject: String, htmlBody: String, plainText: String) {
        let system = """
        You are a professional newsletter content writer for Harpocrates Solutions GmbH, a RegTech company specializing in automated compliance monitoring.
        Return a JSON object with: subject (under 60 chars), htmlBody (full HTML with inline CSS), plainText.
        HTML: use inline styles, brand colors #1a1a2e #16213e #0f3460 #e94560, max-width 600px, include {{UNSUBSCRIBE_URL}}.
        ALL numbers/stats MUST cite source (e.g. Quelle: EBA Report 2024). No hallucination. EU/DACH focus.
        ENTSCHEIDER-FOKUS: Clear action recommendations for C-Level. Compliance as competitive advantage.
        Return ONLY valid JSON: { subject, htmlBody, plainText }
        """
        let industryContext = industries.isEmpty ? "various EU industries" : industries.joined(separator: ", ")
        let user = """
        Write a newsletter about: \(topic.promptPrefix) \(industryContext)
        Topic: \(topic.rawValue). Audience: Compliance officers, risk managers in \(industryContext).
        Requirements: 3-4 paragraphs, specific EU regulatory references (DORA, NIS2, EU AI Act, CSRD, MiFID II),
        regulatory deadlines, penalty amounts in EUR, Regulatory Radar section with 2-3 bullets.
        Harpocrates COMPLY as the solution. Return ONLY valid JSON.
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 6000)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (subject: "Harpocrates Compliance Update", htmlBody: content, plainText: content)
        }
        return (subject: dict["subject"] as? String ?? "Harpocrates Compliance Update",
                htmlBody: dict["htmlBody"] as? String ?? content,
                plainText: dict["plainText"] as? String ?? content)
    }

    // MARK: - 8) Social Post generieren
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform, industries: [String], apiKey: String) async throws -> SocialPost {
        let system = """
        You are a LinkedIn content expert for Harpocrates Solutions GmbH (comply.reg), a RegTech company.
        Write professional LinkedIn posts focused EXCLUSIVELY on EU regulatory compliance, RegTech, FinTech,
        GDPR, DORA, EU AI Act, MiCA, AML/KYC, ISO 27001, NIS2, CSRD, MiFID II, Basel IV, BaFin regulations.

        CRITICAL CONTENT RULES:
        - Every post MUST contain at least 2-3 specific numbers or facts from verifiable EU sources
        - Every statistic MUST cite source: e.g. (Quelle: EBA Report 2024) or (Source: BaFin Annual Report 2024)
        - DO NOT hallucinate or invent any numbers, statistics, or facts
        - DO NOT use markdown formatting: no **, no *, no #, no _. Plain text only
        - DO NOT use emojis or emoticons of any kind
        - All currency values MUST be in EUR. Convert USD/GBP to approximate EUR
        - Focus EXCLUSIVELY on EU/DACH/European market and institutions
        - Only use real, verifiable data from: EU Commission, BaFin, EBA, ECB, Big4 reports, Gartner, Forrester

        ENTSCHEIDER-FOKUS:
        - Every post motivates C-Level and Heads of Compliance to take action
        - Frame compliance as competitive advantage, not cost
        - Use urgency: regulatory deadlines, EUR penalty amounts, competitive pressure
        - End with a concise, sharp question to drive engagement
        - Position Harpocrates COMPLY as the solution

        FORMATTING:
        - Plain text only - LinkedIn native format
        - Use line breaks for readability
        - Strong hook in first line (no emoji)
        - For emphasis use CAPS sparingly (max 1-2 words)
        - Max 3000 characters

        Return JSON: { content: string, hashtags: [string], sources: [string] }
        """
        let industryContext = industries.isEmpty ? "EU financial services, RegTech, FinTech" : industries.joined(separator: ", ")
        let user = """
        Write a LinkedIn post about: \(topic.promptPrefix) \(industryContext)
        Topic: \(topic.rawValue). Company: Harpocrates Solutions GmbH - Automated Compliance Monitoring.
        Include 2-3 real EU statistics with sources. No markdown. No emojis. EUR only.
        Return ONLY valid JSON: { content, hashtags, sources }
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 2000)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SocialPost(platform: platform, content: stripMarkdown(content))
        }
        let hashtags = (dict["hashtags"] as? [String]) ?? []
        return SocialPost(platform: platform,
                          content: stripMarkdown(dict["content"] as? String ?? content),
                          hashtags: hashtags)
    }

    // MARK: - Helpers
    private func stripMarkdown(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "* ", with: "")
        let lines = s.components(separatedBy: "\n")
        s = lines.map { line in
            var l = line
            while l.hasPrefix("#") { l = String(l.dropFirst()) }
            return l.hasPrefix(" ") ? String(l.dropFirst()) : l
        }.joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
