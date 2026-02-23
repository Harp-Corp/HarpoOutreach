import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar-pro"

    // Standard-Footer fuer alle generierten Inhalte (LinkedIn, Newsletter, etc.)
    static let companyFooter = "\n\n\u{1F517} www.harpocrates-corp.com | \u{1F4E7} info@harpocrates-corp.com"

    // Stellt sicher, dass der Footer IMMER am Ende des Contents steht
    // Entfernt existierenden Footer und haengt ihn frisch an
    static func ensureFooter(_ content: String) -> String {
        var clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Entferne existierenden Footer falls vorhanden (egal ob teilweise oder komplett)
        if let range = clean.range(of: "\u{1F517} www.harpocrates-corp.com") {
            clean = String(clean[clean.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: auch altes Format ohne Emoji entfernen
        if let range = clean.range(of: " www.harpocrates-corp.com") {
            clean = String(clean[clean.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean + companyFooter
    }

    // Entfernt Hashtag-Zeilen am Ende des Contents (verhindert Dopplungen)
    static func stripTrailingHashtags(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var foundNonHashtag = false
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && !foundNonHashtag { continue }
            if trimmed.hasPrefix("#") && !foundNonHashtag { continue }
            foundNonHashtag = true
            result.insert(line, at: 0)
        }
        return result.joined(separator: "\n")
    }

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
        request.timeoutInterval = 120

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

    // MARK: - 1) Unternehmen finden (25 Ergebnisse)
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
        Return ALL 25 companies as a single JSON array. Do not truncate. Do not stop early. Count your results before returning - there must be 25 objects in the array.
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 8000)
        return parseJSON(content).map { d in
            Company(
                name: d["name"] ?? "Unknown",
                industry: d["industry"] ?? industry.rawValue,
                region: d["region"] ?? region.rawValue,
                website: d["website"] ?? "",
                linkedInURL: d["linkedInURL"] ?? "",
                description: d["description"] ?? ""
            )
        }
    }

    // MARK: - 2) Ansprechpartner finden - Breite Suche ueber ALLE Quellen
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
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
        - theorg.com organizational charts
        Return a JSON array of objects. Each object must have these fields:
        - name: Full name of the person
        - title: Their job title
        - email: Email if found, empty string if not
        - linkedInURL: LinkedIn profile URL if found, empty string if not
        - source: Where you found this person
        IMPORTANT: Return ALL people you find. Include anyone in compliance, legal, regulatory, data protection, or risk management roles.
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
        Search LinkedIn, \(company.website), theorg.com, business directories, press releases, XING, annual reports.
        Return ALL people you find as JSON array.
        """
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
        var allCandidates = parseJSON(content1)

        if allCandidates.count < 3 {
            let system2 = """
            You are a research assistant. Search the web for executives and senior managers at a specific company.
            Return a JSON array with fields: name, title, email, linkedInURL, source.
            Search LinkedIn, company websites, theorg.com, news, business directories, XING, and any other public source.
            Return ALL people you find. Include email if available, empty string if not.
            """
            let user2 = """
            Find senior managers and executives at \(company.name) who work in compliance, legal, regulatory, risk, or data protection.
            Also search for: Vorstand, Geschaeftsfuehrung, C-Level executives at \(company.name).
            Website: \(company.website)
            Search broadly across LinkedIn, XING, theorg.com, \(company.website), Google, business registers.
            Return JSON array with: name, title, email, linkedInURL, source.
            """
            do {
                let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 4000)
                let moreResults = parseJSON(content2)
                for candidate in moreResults {
                    let name = candidate["name"] ?? ""
                    if !name.isEmpty && !allCandidates.contains(where: { normalizeName($0["name"] ?? "") == normalizeName(name) }) {
                        allCandidates.append(candidate)
                    }
                }
            } catch { }
        }

        var leads: [Lead] = []
        for candidate in allCandidates {
            let name = candidate["name"] ?? ""
            if name.isEmpty || name == "Unknown" || name.count < 3 { continue }
            let email = candidate["email"] ?? ""
            let linkedIn = candidate["linkedInURL"] ?? ""
            let source = candidate["source"] ?? "Perplexity Search"
            let title = candidate["title"] ?? ""
            if leads.contains(where: { normalizeName($0.name) == normalizeName(name) }) { continue }
            leads.append(Lead(
                name: name, title: title, company: company.name,
                email: cleanEmail(email), emailVerified: false,
                linkedInURL: linkedIn, responsibility: title,
                status: .identified, source: source
            ))
        }
        return leads
    }

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

    private func cleanEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") && trimmed.contains(".") {
            return trimmed.lowercased()
        }
        return ""
    }

    // MARK: - 3) Email verifizieren - Multi-Pass Quellensuche
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        var allEmails: [(email: String, source: String, confidence: String)] = []
        var allNotes: [String] = []

        let system1 = """
        You are an expert at finding verified business email addresses from public sources.
        Search EXHAUSTIVELY across ALL of these sources:
        1. LinkedIn - profile page, contact info section
        2. Company website - team page, about us, leadership, impressum, Kontakt
        3. theorg.com - organizational charts
        4. XING profiles (critical for DACH region)
        5. Business directories: ZoomInfo, Apollo.io, Lusha, RocketReach, Hunter.io
        6. Financial databases: Bloomberg, Reuters, Crunchbase
        7. Press releases and news articles
        8. Conference speaker listings
        9. Regulatory filings (BaFin, SEC, Handelsregister)
        10. Google search: "firstname lastname email company"
        Return a JSON object with:
        - emails: array of objects, each with {email, source, confidence} where confidence is "high", "medium", or "low"
        - company_email_pattern: the naming pattern used at this company
        - pattern_examples: array of other verified emails at the same company
        - notes: string with additional context
        """
        let user1 = """
        Find the business email address for:
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company)
        Current email (may be empty or wrong): \(lead.email)
        LinkedIn: \(lead.linkedInURL)
        Search ALL sources. Return JSON.
        """
        do {
            let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
            let json1 = cleanJSON(content1)
            if let data = json1.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let emails = dict["emails"] as? [[String: Any]] {
                    for e in emails {
                        if let addr = e["email"] as? String, !addr.isEmpty, addr.contains("@") {
                            allEmails.append((email: addr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), source: e["source"] as? String ?? "Search", confidence: e["confidence"] as? String ?? "medium"))
                        }
                    }
                }
                if let pattern = dict["company_email_pattern"] as? String, !pattern.isEmpty { allNotes.append("Pattern: \(pattern)") }
                if let notes = dict["notes"] as? String, !notes.isEmpty { allNotes.append(notes) }
            }
        } catch { allNotes.append("Pass 1: \(error.localizedDescription)") }

        let system2 = """
        You are an email verification specialist. Given a person and candidate emails, verify them.
        Return JSON with: best_email, verified (boolean), confidence, verification_sources, alternative_emails, reasoning.
        """
        let candidateEmails = allEmails.map { $0.email }.prefix(5).joined(separator: ", ")
        let user2 = """
        Verify the best email for: \(lead.name), \(lead.title) at \(lead.company)
        LinkedIn: \(lead.linkedInURL)
        Candidate emails: \(candidateEmails.isEmpty ? "none found yet" : candidateEmails)
        Return verification result as JSON.
        """
        do {
            let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 3000)
            let json2 = cleanJSON(content2)
            if let data = json2.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let bestEmail = dict["best_email"] as? String, !bestEmail.isEmpty, bestEmail.contains("@") {
                    let conf = dict["confidence"] as? String ?? "medium"
                    let verified = dict["verified"] as? Bool ?? false
                    allEmails.insert((email: bestEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), source: "Cross-verification", confidence: verified ? "high" : conf), at: 0)
                }
                if let alts = dict["alternative_emails"] as? [String] {
                    for alt in alts where alt.contains("@") && !alt.isEmpty {
                        let cleanAlt = alt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !allEmails.contains(where: { $0.email == cleanAlt }) {
                            allEmails.append((email: cleanAlt, source: "Alternative", confidence: "low"))
                        }
                    }
                }
                if let reasoning = dict["reasoning"] as? String, !reasoning.isEmpty { allNotes.append(reasoning) }
            }
        } catch { allNotes.append("Pass 2: \(error.localizedDescription)") }

        let uniqueEmails = Dictionary(grouping: allEmails, by: { $0.email })
        let best = allEmails.first(where: { $0.confidence == "high" })
            ?? allEmails.first(where: { $0.confidence == "medium" && (uniqueEmails[$0.email]?.count ?? 0) > 1 })
            ?? allEmails.first(where: { $0.confidence == "medium" })
            ?? allEmails.first
        let finalEmail = best?.email ?? lead.email
        let isVerified = best?.confidence == "high" || (best != nil && (uniqueEmails[best!.email]?.count ?? 0) > 1) || best?.confidence == "medium"
        let notes = ([best.map { "Best: \($0.email) (\($0.source), \($0.confidence) confidence)" } ?? "No email found", "Total candidates: \(allEmails.count)"] + allNotes).joined(separator: " | ")
        return (email: cleanEmail(finalEmail.isEmpty ? lead.email : finalEmail), verified: isVerified, notes: String(notes.prefix(500)))
    }

    // MARK: - 4) Branchen-Challenges recherchieren
    func researchChallenges(company: Company, apiKey: String) async throws -> String {
        let system = "You research specific regulatory and compliance challenges. Return a concise summary of key challenges. ALWAYS respond in English."
        let user = "What are the top 3-5 regulatory compliance challenges for \(company.name) in \(company.industry)? Focus on current regulations, upcoming changes, and pain points. Respond in English."
        return try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
    }

    // MARK: - 5) Personalisierte Email erstellen - ALWAYS IN ENGLISH
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = """
        You write professional B2B outreach emails. CRITICAL RULES:
        1. ALWAYS write in English - no German, no other language.
        2. Write a personalized, non-salesy email that provides genuine value.
        3. Reference SPECIFIC challenges the recipient's company faces based on their industry.
        4. Show you understand their role and responsibilities.
        5. Keep it under 150 words, personal, value-focused. No hard sell.
        6. The email must feel like it was written specifically for this person, not a template.
        Return ONLY a valid JSON object with: subject, body
        """
        let user = """
        Write a cold outreach email from \(senderName) at Harpocrates Corp (RegTech company) to:
        Name: \(lead.name), Title: \(lead.title), Company: \(lead.company)
        Their specific challenges: \(challenges)
        Our solution: comply.reg - Automated compliance monitoring, regulatory change tracking, risk assessment.
        
        IMPORTANT:
        - Write ENTIRELY in English
        - Reference their specific regulatory challenges (e.g. DORA, NIS2, GDPR specifics)
        - Make the subject line compelling and specific to their situation
        - Include a soft CTA (e.g. brief call, sharing a relevant case study)
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

    // MARK: - 6) Follow-up Email erstellen - ALWAYS IN ENGLISH
    func draftFollowUp(lead: Lead, originalEmail: String, followUpEmail: String = "", replyReceived: String = "", senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = """
        You write professional follow-up emails for B2B outreach. CRITICAL RULES:
        1. ALWAYS write in English - no German, no other language.
        2. Based on previous emails and any replies, write a follow-up that:
           - References the previous conversation naturally
           - If there was a reply: acknowledge it and continue the dialogue
           - If there was no reply: add new value and a different angle
           - Keeps it under 150 words, professional, value-focused
           - Do NOT repeat the same pitch. Bring fresh insights or a relevant case study.
        3. Make the content specifically relevant to the recipient's company and role.
        Return ONLY a valid JSON object with: subject, body
        """
        var conversationContext = "Previous email sent to \(lead.name) at \(lead.company):\n\(originalEmail)"
        if !followUpEmail.isEmpty { conversationContext += "\n\nPrevious follow-up sent:\n\(followUpEmail)" }
        if !replyReceived.isEmpty { conversationContext += "\n\nReply received from \(lead.name):\n\(replyReceived)" }
        let user = """
        Write a follow-up email in English from \(senderName) at Harpocrates Corp.
        CONVERSATION HISTORY:
        \(conversationContext)
        Based on the above, write the next follow-up. If a reply was received, respond to it directly.
        If no reply, try a different angle to provide value. Write ENTIRELY in English.
        Return JSON with: subject, body
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Following up - \(lead.company)", body: content)
        }
        let rawBody2 = dict["body"] as? String ?? content
        return OutboundEmail(subject: dict["subject"] as? String ?? "Following up - \(lead.company)", body: stripCitations(rawBody2))
    }

    // MARK: - 8) Social Post generieren - ALWAYS IN ENGLISH, LinkedIn value-focused
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform, industries: [String], existingPosts: [SocialPost] = [], apiKey: String) async throws -> SocialPost {
        let existingTitles = existingPosts.prefix(10).map { String($0.content.prefix(80)) }.joined(separator: "\n- ")
        let dupeContext = existingPosts.isEmpty ? "" : "\n\nALREADY POSTED CONTENT (DO NOT REPEAT):\n- " + existingTitles

        let system = """
        You are a social media expert for Harpocrates Corp and the product comply.reg.
        comply.reg is a RegTech SaaS platform for automated compliance monitoring, regulatory change management, and risk assessment for fintech, banks, and regulated enterprises.

        MANDATORY RULES for every post:
        1. LANGUAGE: Write ENTIRELY in English. No German, no other language.
        2. FACTS & FIGURES: Every post MUST contain at least 1-2 concrete numbers, statistics, or data (e.g. fines up to 10M EUR, 72h reporting obligation, DORA effective from Jan 17 2025)
        3. SOURCE CITATION: Numbers and facts MUST be cited with source. Format: (Source: EBA, BaFin, ECB, ESMA, EU Official Journal, etc.)
        4. NO HALLUCINATIONS: Only use verifiable facts. If unsure, do not include specific numbers.
        5. COMPLY.REG RELEVANCE: Post must address problems that comply.reg solves.
        6. NO DUPLICATE: Topic and hook must differ from already posted content.
        7. FOOTER: The footer is added AUTOMATICALLY. Do NOT generate any footer in the post content!
        8. VALUE-DRIVEN: Every post must provide genuine insight or actionable knowledge for compliance professionals.
        Return JSON: {"content": "...", "hashtags": [...]}
        """
        let industryContext = industries.isEmpty ? "Financial Services, RegTech, Compliance" : industries.joined(separator: ", ")
        let user = """
        Write a \(platform.rawValue) post for Harpocrates Corp / comply.reg.
        Topic: \(topic.rawValue) - \(topic.promptPrefix) \(industryContext)

        REQUIREMENTS:
        - Write ENTIRELY in English
        - Hook in line 1 (number or provocative thesis)
        - At least 1 concrete number/statistic with source in parentheses
        - Reference DORA, NIS2, GDPR, MiCA, EU AI Act, CSRD or current EU regulations
        - Question or CTA at the end
        - Mention comply.reg naturally (no hard sell)
        - LinkedIn: 150-250 words, line breaks for readability\(dupeContext)
        Hashtags: 5-7 from: #DORA #NIS2 #GDPR #RegTech #Compliance #FinTech #RegulatoryCompliance #comply #RiskManagement #AML #BaFin #EBA
        Return ONLY valid JSON: {"content": "...", "hashtags": [...]}
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 2000)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SocialPost(platform: platform, content: Self.ensureFooter(content))
        }
        let rawContent = dict["content"] as? String ?? content
        let hashtags = (dict["hashtags"] as? [String]) ?? []
        let hashtagLine = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        var fullContent = Self.stripTrailingHashtags(rawContent)
        if !hashtagLine.isEmpty { fullContent += "\n\n" + hashtagLine }
        fullContent = Self.ensureFooter(fullContent)
        return SocialPost(platform: platform, content: fullContent, hashtags: hashtags)
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
