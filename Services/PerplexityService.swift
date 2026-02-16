import Foundation

class PerplexityService {
    private let baseURL = "https://api.perplexity.ai"
    
    // MARK: - 1) Unternehmen finden
    func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
        let prompt = """
        Find 5-10 major \(industry.searchTerms) companies in \(region.countries).
        For each company provide:
        - Company name
        - Industry sector
        - Website URL
        - Brief description (1-2 sentences)
        
        Return ONLY a JSON array with this exact structure:
        [{"name": "Company Name", "industry": "\(industry.rawValue)", "region": "\(region.rawValue)", "website": "https://...", "description": "...", "source": "perplexity"}]
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return parseCompanies(from: response, industry: industry.rawValue, region: region.rawValue)
    }
    
    // MARK: - 2) Kontakte finden
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        let prompt = """
        Find 3-5 compliance, regulatory affairs, or data protection officers at \(company.name).
        For each person provide:
        - Full name
        - Job title
        - Email address (if publicly available)
        - LinkedIn profile URL
        - Areas of responsibility
        
        Return ONLY a JSON array with this structure:
        [{"name": "Full Name", "title": "Job Title", "email": "email@company.com", "linkedInURL": "https://linkedin.com/in/...", "responsibility": "Compliance, Data Protection"}]
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return parseLeads(from: response, company: company)
    }
    
    // MARK: - 3) Email verifizieren
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        let prompt = """
        Verify the email address for \(lead.name) at \(lead.company.name).
        Check if \(lead.email) is valid or find the correct business email.
        
        Return ONLY JSON:
        {"email": "verified@email.com", "verified": true, "notes": "Email verified via company directory"}
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return parseEmailVerification(from: response, currentEmail: lead.email)
    }
    
    // MARK: - 4) Challenges recherchieren
    func researchChallenges(company: Company, apiKey: String) async throws -> String {
        let prompt = """
        Research current regulatory compliance challenges for \(company.name) in the \(company.industry) sector.
        Focus on:
        - Recent regulatory changes (GDPR, NIS2, DORA, etc.)
        - Industry-specific compliance requirements
        - Data protection obligations
        - Cybersecurity requirements
        
        Provide a concise summary (3-4 sentences) of their key compliance challenges.
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return extractContent(from: response)
    }
    
    // MARK: - 5) Email erstellen
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let prompt = """
        Write a professional cold outreach email in German to \(lead.name) (\(lead.title)) at \(lead.company.name).
        
        Context:
        - Sender: \(senderName) from Harpocrates Corp
        - Harpocrates offers RegTech solutions for compliance management
        - Company challenges: \(challenges)
        
        Requirements:
        - Subject line in German
        - Personalized based on their role and company challenges
        - Brief (max 150 words)
        - Professional tone
        - Clear call-to-action (15-minute intro call)
        - No generic phrases
        
        Return ONLY JSON:
        {"subject": "Subject line", "body": "Email body text"}
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return parseEmail(from: response)
    }
    
    // MARK: - 6) Follow-Up Email
    func draftFollowUp(lead: Lead, originalEmail: OutboundEmail, senderName: String, apiKey: String) async throws -> OutboundEmail {
        let prompt = """
        Write a follow-up email in German to \(lead.name) at \(lead.company.name).
        
        Context:
        - Original email subject: \(originalEmail.subject)
        - No response received after 14 days
        - Sender: \(senderName) from Harpocrates Corp
        
        Requirements:
        - Polite follow-up
        - Add new value (mention recent regulatory development or industry insight)
        - Brief (max 100 words)
        - Renewed call-to-action
        
        Return ONLY JSON:
        {"subject": "Re: \(originalEmail.subject)", "body": "Follow-up email body"}
        """
        
        let response = try await callPerplexity(prompt: prompt, apiKey: apiKey)
        return parseEmail(from: response)
    }
    
    // MARK: - API Call Helper
    private func callPerplexity(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "Invalid URL", code: -1)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "sonar",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides structured data. Always respond in the requested format."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 800
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(PerplexityResponse.self, from: data)
        
        guard let content = response.choices?[0].message?.content else {
            throw NSError(domain: "No content in response", code: -2)
        }
        
        return content
    }
    
    // MARK: - Parsing Helpers
    private func parseCompanies(from response: String, industry: String, region: String) -> [Company] {
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return []
        }
        
        struct CompanyData: Codable {
            let name: String
            let industry: String?
            let region: String?
            let website: String?
            let description: String?
            let source: String?
        }
        
        guard let companies = try? JSONDecoder().decode([CompanyData].self, from: jsonData) else {
            return []
        }
        
        return companies.map { data in
            Company(
                name: data.name,
                industry: data.industry ?? industry,
                region: data.region ?? region,
                website: data.website ?? "",
                description: data.description ?? "",
                source: data.source ?? "perplexity"
            )
        }
    }
    
    private func parseLeads(from response: String, company: Company) -> [Lead] {
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return []
        }
        
        struct LeadData: Codable {
            let name: String
            let title: String
            let email: String?
            let linkedInURL: String?
            let responsibility: String?
        }
        
        guard let leadsData = try? JSONDecoder().decode([LeadData].self, from: jsonData) else {
            return []
        }
        
        return leadsData.map { data in
            Lead(
                name: data.name,
                title: data.title,
                company: company,
                email: data.email ?? "",
                linkedInURL: data.linkedInURL ?? "",
                responsibility: data.responsibility ?? "",
                status: .identified,
                source: "perplexity"
            )
        }
    }
    
    private func parseEmailVerification(from response: String, currentEmail: String) -> (email: String, verified: Bool, notes: String) {
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return (currentEmail, false, "Could not parse verification response")
        }
        
        struct VerificationData: Codable {
            let email: String
            let verified: Bool
            let notes: String
        }
        
        guard let data = try? JSONDecoder().decode(VerificationData.self, from: jsonData) else {
            return (currentEmail, false, "Could not decode verification data")
        }
        
        return (data.email, data.verified, data.notes)
    }
    
    private func parseEmail(from response: String) -> OutboundEmail {
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return OutboundEmail(subject: "Fehler", body: "Email konnte nicht erstellt werden.")
        }
        
        struct EmailData: Codable {
            let subject: String
            let body: String
        }
        
        guard let data = try? JSONDecoder().decode(EmailData.self, from: jsonData) else {
            return OutboundEmail(subject: "Fehler", body: "Email konnte nicht dekodiert werden.")
        }
        
        return OutboundEmail(subject: data.subject, body: data.body)
    }
    
    private func extractJSON(from response: String) -> String? {
        // Try to find JSON array or object in response
        if let startArray = response.range(of: "["),
           let endArray = response.range(of: "]", options: .backwards) {
            return String(response[startArray.lowerBound...endArray.upperBound])
        }
        
        if let startObject = response.range(of: "{"),
           let endObject = response.range(of: "}", options: .backwards) {
            return String(response[startObject.lowerBound...endObject.upperBound])
        }
        
        return nil
    }
    
    private func extractContent(from response: String) -> String {
        // Remove any markdown formatting or extra content
        var content = response
        content = content.replacingOccurrences(of: "```json", with: "")
        content = content.replacingOccurrences(of: "```", with: "")
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content
    }
}
