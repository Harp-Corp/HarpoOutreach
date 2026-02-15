import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"
    private let model = "sonar-pro"

    // MARK: - Generic API Call
    private func callAPI(systemPrompt: String, userPrompt: String,
                         apiKey: String, maxTokens: Int = 4000) async throws -> String {
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
        guard let content = apiResp.choices?.first?.message?.content else {
            throw PplxError.noContent
        }
        return content
    }

    // MARK: - 1) Unternehmen finden
    func findCompanies(industry: Industry, region: Region,
                       apiKey: String) async throws -> [Company] {
        let system = """
        You find real companies. Return ONLY a JSON array of objects with fields:
        "name", "industry", "region", "website", "description".
        No text outside the JSON. Only real, verifiable companies.
        """
        let user = """
        Find 8-10 real \(industry.rawValue) companies in \(region.countries) \
        that are likely to need compliance solutions. Focus on mid-size to large \
        companies in \(industry.searchTerms). Include company website. \
        Return ONLY valid JSON array.
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        return parseJSON(content).map { d in
            Company(name: d["name"] ?? "Unknown",
                    industry: d["industry"] ?? industry.rawValue,
                    region: d["region"] ?? region.rawValue,
                    website: d["website"] ?? "",
                    description: d["description"] ?? "")
        }
    }

    // MARK: - 1b) Spezifisches Unternehmen suchen
    func findSpecificCompany(companyName: String, apiKey: String) async throws -> Company? {
        let system = """
        You research a specific company. Return ONLY a JSON object (NOT an array) with fields:
        "name", "industry", "region", "website", "description".
        If the company doesn't exist or you can't find it, return null.
        No text outside the JSON.
        """
        let user = """
        Research the company: \(companyName)
        
        Find:
        - Full official company name
        - Primary industry (Healthcare, Financial Services, Energy, or Manufacturing)
        - Region/Country where headquartered
        - Official website
        - Brief description
        
        Return ONLY valid JSON object or null if not found.
        """
        
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)
        
        if json.lowercased() == "null" { return nil }
        
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        
        return Company(
            name: dict["name"] ?? companyName,
            industry: dict["industry"] ?? "Unknown",
            region: dict["region"] ?? "Unknown",
            website: dict["website"] ?? "",
            description: dict["description"] ?? ""
        )
    }

    // MARK: - 2) Compliance-Ansprechpartner finden
    func findContacts(company: Company,
                      apiKey: String) async throws -> [Lead] {
        let system = """
        You find real compliance professionals at specific companies.
        Return ONLY a JSON array of objects with fields:
        "name", "title", "linkedInURL", "email", "responsibility", "source".
        Only real, verifiable people. If email unknown use "".
        No fake data. No text outside the JSON.
        """
        let user = """
        Find compliance officers, Chief Compliance Officers, heads of compliance, \
        legal/compliance directors, or managing directors responsible for compliance \
        at \(company.name) (\(company.industry), \(company.region)). \
        Website: \(company.website). \
        Search LinkedIn, company website, press releases, regulatory filings. \
        Include their LinkedIn URL if available. \
        Return ONLY valid JSON array.
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        return parseJSON(content).map { d in
            Lead(name: d["name"] ?? "Unknown",
                 title: d["title"] ?? "",
                 company: company,
                 email: d["email"] ?? "",
                 emailVerified: false,
                 linkedInURL: d["linkedInURL"] ?? "",
                 responsibility: d["responsibility"] ?? "",
                 status: .identified,
                 source: d["source"] ?? "Perplexity Sonar")
        }
    }

    // MARK: - 3) Email verifizieren
    func verifyEmail(lead: Lead,
                     apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        let system = """
        You verify business email addresses. Return ONLY a JSON object with fields:
        "email", "verified" (true/false), "notes".
        Only confirm emails you can verify from public sources.
        Common patterns: firstname.lastname@domain, f.lastname@domain, firstname@domain.
        Check company website, LinkedIn, press releases, conference speakers lists,
        regulatory filings, XING, published articles.
        """
        let user = """
        Find and verify the business email address for:
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company.name)
        Company website: \(lead.company.website)
        Known email so far: \(lead.email)
        LinkedIn: \(lead.linkedInURL)
        
        Search all available sources. If you cannot verify 100%, state that clearly.
        Return ONLY valid JSON object.
        """

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
    func researchChallenges(company: Company,
                            apiKey: String) async throws -> String {
        let system = """
        You are a compliance industry research expert. Write in German.
        Research real, current compliance challenges for the given company and industry.
        Return a structured text (not JSON) with:
        1. Branchenspezifische Compliance-Herausforderungen (3-4 Punkte)
        2. Unternehmensspezifische Themen (2-3 Punkte)
        3. Aktuelle regulatorische Entwicklungen
        Be specific, use real regulations (DORA, NIS2, CSRD, MDR, EU AI Act etc.)
        """
        let user = """
        Research compliance challenges for:
        Company: \(company.name)
        Industry: \(company.industry)
        Region: \(company.region)
        Website: \(company.website)
        Description: \(company.description)
        """

        return try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
    }

    // MARK: - 5) Personalisierte Email drafting
    func draftEmail(lead: Lead, challenges: String, senderName: String,
                    apiKey: String) async throws -> OutboundEmail {
        let system = """
        Du bist ein erfahrener B2B-Vertriebsexperte, der hochgradig personalisierte \
        Outreach-Emails schreibt. Du schreibst für Harpocrates, ein deutsches RegTech-Startup.
        
        ÜBER HARPOCRATES:
        - Produkt: COMPLY – AI-gestützte Compliance-Management-Platform
        - Kernversprechen: Reduziert Compliance-Aufwand um >50% in 3 Monaten
        - Funktionen: Automatisches Monitoring von Regulierungen (EU-Lex, interne Richtlinien), \
          360°-Compliance-Überblick, KI-gestützte Analyse, branchen-agnostisch, skalierbar
        - Website: www.harpocrates-corp.com
        - Zielgruppe: Compliance Officers, Heads of Compliance, GRC-Verantwortliche
        
        DEINE AUFGABE:
        Schreibe eine personalisierte, professionelle Email auf Deutsch, die:
        1. Den Empfänger PERSÖNLICH anspricht (Name, Position, Unternehmen)
        2. SPEZIFISCHE Compliance-Herausforderungen seiner Branche/Firma nennt
        3. Zeigt, dass du recherchiert hast (konkrete Regulierungen/Entwicklungen erwähnen)
        4. Einen klaren Mehrwert bietet (nicht nur Features, sondern Lösung für SEINE Probleme)
        5. Mit einem klaren, unaufdringlichen Call-to-Action endet
        
        STIL:
        - Professionell, aber persönlich und warm
        - Keine generischen Phrasen wie "Ich hoffe diese Email findet Sie gut"
        - Direkt zum Punkt, max. 180 Wörter Body
        - Nutze konkrete Zahlen/Fakten aus der Recherche
        - Zeige Verständnis für die Situation, nicht nur Produktwerbung
        
        OUTPUT:
        Returniere NUR ein JSON-Objekt mit den Feldern "subject" und "body".
        Kein Text vor oder nach dem JSON.
        """
        
        let user = """
        EMPFÄNGER:
        Name: \(lead.name)
        Position: \(lead.title)
        Unternehmen: \(lead.company.name)
        Branche: \(lead.company.industry)
        Region: \(lead.company.region)
        LinkedIn: \(lead.linkedInURL)
        Verantwortungsbereich: \(lead.responsibility)
        
        RECHERCHIERTE COMPLIANCE-HERAUSFORDERUNGEN:
        \(challenges)
        
        ABSENDER:
        Name: \(senderName)
        Position: CEO & Founder, Harpocrates Solutions GmbH
        Email: mf@harpocrates-corp.com
        
        ANWEISUNGEN:
        - Betreff: Kurz, spezifisch, kein Clickbait. Erwähne das Unternehmen oder die konkrete Challenge.
        - Eröffnung: Persönlich, zeige dass du dich mit \(lead.company.name) beschäftigt hast
        - Hauptteil: Nenne 1-2 KONKRETE Herausforderungen aus der Recherche, dann zeige wie COMPLY \
          genau DIESE löst
        - Schluss: Einfacher CTA (z.B. "15-Minuten-Demo vereinbaren" oder "Kurzes Gespräch nächste Woche")
        - Ton: Respektvoll, auf Augenhöhe, nicht verkäuferisch
        
        Schreibe jetzt die Email. Return NUR JSON mit "subject" und "body".
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user,
                                       apiKey: apiKey, maxTokens: 1500)
        let json = cleanJSON(content)

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw PplxError.parseError
        }

        return OutboundEmail(
            subject: dict["subject"] ?? "Compliance Automation für \(lead.company.name)",
            body: dict["body"] ?? ""
        )
    }

    // MARK: - 6) Follow-Up Email
    func draftFollowUp(lead: Lead, originalEmail: OutboundEmail, senderName: String,
                       apiKey: String) async throws -> OutboundEmail {
        let system = """
        You write follow-up emails in German for Harpocrates. \
        Reference the original email. Be brief, friendly, add new value. \
        Max 150 words. Return ONLY JSON with "subject" and "body".
        """
        let user = """
        Write a follow-up email for:
        Recipient: \(lead.name), \(lead.title) at \(lead.company.name)
        Original subject: \(originalEmail.subject)
        Original sent date: \(lead.dateEmailSent?.formatted() ?? "unknown")
        Sender: \(senderName)
        
        Reference the first email, add new insight or value proposition.
        Return ONLY JSON with "subject" and "body".
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey)
        let json = cleanJSON(content)

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw PplxError.parseError
        }

        return OutboundEmail(
            subject: dict["subject"] ?? "Re: \(originalEmail.subject)",
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
            print("JSON Parse Error: \(error)\n\(json.prefix(300))")
