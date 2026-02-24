// HarpoOutreachWeb - Server-side Perplexity AI Service
// Adapted from macOS app for Vapor server (no Foundation URLSession)
import Foundation
import Vapor
import HarpoOutreachCore

actor PerplexityServiceWeb {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar-pro"
    private let apiKey: String
    private let client: Client
    private let logger: Logger

    init(apiKey: String, client: Client, logger: Logger) {
        self.apiKey = apiKey
        self.client = client
        self.logger = logger
    }

    // MARK: - Generic API Call
    private func callAPI(systemPrompt: String, userPrompt: String, maxTokens: Int = 4000) async throws -> String {
        let body = PplxRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            max_tokens: maxTokens,
            web_search_options: .init(search_context_size: "high")
        )
        let uri = URI(string: apiURL)
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        headers.add(name: .contentType, value: "application/json")
        let response = try await client.post(uri, headers: headers) { req in
            try req.content.encode(body, as: .json)
        }
        guard response.status == .ok else {
            let errBody = response.body.map { String(buffer: $0) } ?? ""
            throw Abort(.badGateway, reason: "Perplexity API \(response.status.code): \(String(errBody.prefix(300)))")
        }
        let apiResp = try response.content.decode(PplxResponse.self)
        guard let content = apiResp.choices?.first?.message?.content else {
            throw Abort(.badGateway, reason: "Perplexity returned no content")
        }
        return content
    }

    // MARK: - Find Companies
    func findCompanies(industry: Industry, region: Region) async throws -> [CompanyDTO] {
        let system = """
        You are a B2B company research assistant. Return EXACTLY 25 real companies as a JSON array.
        Each object MUST have: name, industry, region, website, linkedInURL, description, size, country.
        Return ONLY valid JSON array. No markdown, no explanation.
        """
        let user = """
        Find exactly 25 real \(industry.shortName) companies in \(region.countries).
        Revenue > 50M EUR, 200+ employees, currently active.
        Return as JSON array.
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, maxTokens: 8000)
        let parsed = parseJSON(content)
        return parsed.map { d in
            CompanyDTO(
                name: d["name"] ?? "Unknown",
                industry: d["industry"] ?? industry.rawValue,
                region: d["region"] ?? region.rawValue,
                website: d["website"] ?? "",
                linkedInURL: d["linkedInURL"] ?? "",
                description: d["description"] ?? "",
                size: d["size"] ?? "",
                country: d["country"] ?? ""
            )
        }
    }

    // MARK: - Draft Email
    func draftEmail(lead: LeadDTO, senderName: String) async throws -> EmailDraftDTO {
        let challenges = try await researchChallenges(company: lead.company, industry: lead.title)
        let system = """
        You write professional B2B outreach emails. ALWAYS in English.
        Personalized, non-salesy, under 150 words, value-focused.
        Reference SPECIFIC challenges. Return JSON: {"subject": "...", "body": "..."}
        """
        let user = """
        Write a cold outreach email from \(senderName) at Harpocrates Corp to:
        Name: \(lead.name), Company: \(lead.company)
        Challenges: \(challenges)
        Solution: comply.reg - Automated compliance monitoring.
        Return JSON with: subject, body
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user)
        let json = cleanJSON(content)
        if let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return EmailDraftDTO(
                leadId: lead.id,
                leadName: lead.name,
                leadEmail: lead.email,
                companyName: lead.company,
                subject: dict["subject"] as? String ?? "Compliance Solutions",
                body: stripCitations(dict["body"] as? String ?? content)
            )
        }
        return EmailDraftDTO(leadId: lead.id, leadName: lead.name, leadEmail: lead.email,
                           companyName: lead.company, subject: "Compliance Solutions", body: content)
    }

    // MARK: - Generate Social Post
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform, industries: [String]) async throws -> SocialPostDTO {
        let system = """
        You are a social media expert for Harpocrates Corp / comply.reg.
        RULES: Write in English. Include facts with sources. No hallucinations.
        Return JSON: {"content": "...", "hashtags": [...]}
        """
        let industryCtx = industries.isEmpty ? "Financial Services, RegTech" : industries.joined(separator: ", ")
        let user = """
        Write a \(platform.rawValue) post. Topic: \(topic.rawValue) for \(industryCtx).
        Include concrete numbers with sources. 150-250 words for LinkedIn.
        Hashtags: 5-7 from #DORA #NIS2 #GDPR #RegTech #Compliance #FinTech
        Return JSON: {"content": "...", "hashtags": [...]}
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, maxTokens: 2000)
        let json = cleanJSON(content)
        if let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let rawContent = dict["content"] as? String ?? content
            let hashtags = (dict["hashtags"] as? [String]) ?? []
            return SocialPostDTO(platform: platform, content: rawContent, hashtags: hashtags)
        }
        return SocialPostDTO(platform: platform, content: content)
    }

    // MARK: - Research Challenges
    private func researchChallenges(company: String, industry: String) async throws -> String {
        let system = "You research regulatory compliance challenges. Return concise summary. Respond in English."
        let user = "Top 3-5 regulatory compliance challenges for \(company) in \(industry)? Focus on current regulations."
        return try await callAPI(systemPrompt: system, userPrompt: user, maxTokens: 2000)
    }

    // MARK: - JSON Helpers
    private func stripCitations(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "\\s*\\[\\d+(,\\s*\\d+)*\\]") {
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
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.map { dict in
                var result: [String: String] = [:]
                for (key, value) in dict { result[key] = "\(value)" }
                return result
            }
        }
        return []
    }
}

// MARK: - Perplexity API Structures
struct PplxRequest: Content {
    let model: String
    let messages: [Message]
    let max_tokens: Int
    let web_search_options: WebSearchOptions
    struct Message: Content { let role: String; let content: String }
    struct WebSearchOptions: Content { let search_context_size: String }
}
struct PplxResponse: Content {
    let choices: [Choice]?
    struct Choice: Content { let message: Msg? }
    struct Msg: Content { let content: String? }
}
