import Foundation

class PerplexityService {
    private let apiURL = "https://api.perplexity.ai/chat/completions"

    // Model selection per task type – mirrors Python MODEL_FAST / MODEL_REASONING
    private let modelFast      = "sonar-pro"
    private let modelReasoning = "sonar-reasoning-pro"

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

    // MARK: - Generic Compliance Fallback

    /// Detects when Perplexity couldn't find useful information about a company.
    /// Mirrors Python _is_unknown_company().
    static func isUnknownCompany(_ content: String) -> Bool {
        let lower = content.lowercased()
        let indicators = [
            "nicht bekannt",
            "not known",
            "no information",
            "keine informationen",
            "could not find",
            "unable to find",
            "no results",
            "i could not",
            "i couldn't",
            "no specific",
            "not publicly available",
            "nicht öffentlich",
            "business model is unclear",
            "geschäftsmodell",
            "does not appear to be",
            "no publicly available"
        ]
        let hitCount = indicators.filter { lower.contains($0) }.count
        // Two or more indicators, or very short response with one indicator
        return hitCount >= 2 || (content.trimmingCharacters(in: .whitespacesAndNewlines).count < 100 && hitCount >= 1)
    }

    /// Returns generic EU compliance challenges when company-specific info is unavailable.
    /// Mirrors Python _generic_compliance_challenges().
    static func genericComplianceChallenges(companyName: String, industry: String) -> String {
        let industryHint = industry.isEmpty ? "" : " in the \(industry) sector"
        return """
Generic EU Regulatory Compliance Challenges for \(companyName)\(industryHint):

1. GDPR (General Data Protection Regulation): All EU-based companies must ensure lawful data processing, maintain Records of Processing Activities (ROPA), respond to Data Subject Access Requests (DSARs) within 30 days, and report data breaches to supervisory authorities within 72 hours. Non-compliance fines up to EUR 20M or 4% of global annual turnover.

2. NIS2 Directive (Network and Information Security): Effective October 2024, NIS2 significantly expands the scope of cybersecurity obligations across the EU. Companies must implement risk management measures, supply chain security assessments, and incident reporting within 24 hours. Fines up to EUR 10M or 2% of global turnover.

3. CSRD (Corporate Sustainability Reporting Directive): Phased implementation 2024-2026 requires detailed ESG reporting aligned with European Sustainability Reporting Standards (ESRS). Mandatory double materiality assessments and third-party assurance.

4. EU AI Act: Effective August 2024 with phased compliance deadlines through 2026. Requires risk classification of AI systems, transparency obligations, and conformity assessments for high-risk AI. Fines up to EUR 35M or 7% of global turnover.

5. AML/CFT Regulations: The EU Anti-Money Laundering Authority (AMLA) starts operations in 2025. Enhanced due diligence requirements, beneficial ownership transparency, and cross-border cooperation obligations.

Key Compliance Deadlines:
- NIS2 transposition: October 2024 (enforcement ongoing)
- CSRD first reports: FY2024 for large PIEs, FY2025 for large companies
- EU AI Act prohibited practices: February 2025
- EU AI Act high-risk obligations: August 2026

These regulations create significant operational complexity, requiring continuous monitoring of regulatory changes, gap analyses, and cross-departmental coordination.
"""
    }

    // MARK: - Generic API Call (mit Retry bei temporaeren Fehlern)
    private func callAPI(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String,
        maxTokens: Int = 4000,
        model: String? = nil
    ) async throws -> String {
        let resolvedModel = model ?? modelFast
        let requestBody = PerplexityRequest(
            model: resolvedModel,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            max_tokens: maxTokens,
            web_search_options: .init(search_context_size: "high")
        )

        let maxRetries = 3
        var lastError: Error = PplxError.invalidResponse

        for attempt in 1...maxRetries {
            var request = URLRequest(url: URL(string: apiURL)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)
            request.timeoutInterval = 120

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw PplxError.invalidResponse }

                if http.statusCode == 200 {
                    let apiResp = try JSONDecoder().decode(PerplexityResponse.self, from: data)
                    guard let content = apiResp.choices?[0].message?.content else { throw PplxError.noContent }
                    return content
                }

                // Temporaere Fehler (429, 500, 502, 503, 504) -> retry mit Backoff
                let retryableCodes = [429, 500, 502, 503, 504]
                if retryableCodes.contains(http.statusCode) && attempt < maxRetries {
                    let delay = UInt64(attempt) * 3_000_000_000 // 3s, 6s
                    print("[PerplexityAPI] HTTP \(http.statusCode) - Retry \(attempt)/\(maxRetries) in \(attempt * 3)s...")
                    try? await Task.sleep(nanoseconds: delay)
                    lastError = PplxError.apiError(code: http.statusCode, message: "Server temporarily unavailable (HTTP \(http.statusCode))")
                    continue
                }

                // Nicht-temporaerer Fehler oder letzter Retry -> saubere Fehlermeldung
                let body = String(data: data, encoding: .utf8) ?? ""
                // HTML-Antworten kuerzen (z.B. Cloudflare 502-Seiten)
                let cleanMessage = body.contains("<!DOCTYPE") || body.contains("<html")
                    ? "Server temporarily unavailable (HTTP \(http.statusCode))"
                    : String(body.prefix(300))
                throw PplxError.apiError(code: http.statusCode, message: cleanMessage)

            } catch let error as PplxError {
                throw error  // Eigene Fehler direkt werfen
            } catch {
                // Netzwerkfehler (Timeout etc.) -> retry
                if attempt < maxRetries {
                    let delay = UInt64(attempt) * 3_000_000_000
                    print("[PerplexityAPI] Network error - Retry \(attempt)/\(maxRetries): \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: delay)
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    // MARK: - 1) Unternehmen finden (25 Ergebnisse) mit Mitarbeiterzahl
    func findCompanies(industry: Industry, region: Region, apiKey: String) async throws -> [Company] {
        let system = """
        You are a B2B company research assistant specializing in European enterprise companies and their regulatory compliance landscape.
        You MUST return EXACTLY 25 real companies as a JSON array.
        Each object MUST have: name, industry, region, website, linkedInURL, description, size, country, employees, nace_code, founded_year, revenue_range, key_regulations.

        CRITICAL RULES:
        - Return ONLY valid JSON. No markdown, no explanation.
        - All 25 companies must be REAL, currently operating.
        - Full website URL (https://...) and LinkedIn company page URL.
        - "employees" = realistic integer. Research the ACTUAL current number. NEVER use 0.
        - "key_regulations" = specific regulations that apply (e.g. "DORA, NIS2, GDPR, MiCA, PSD2, CSRD, EU AI Act, AML6, AMLD").
        - "revenue_range" = approximate revenue (e.g. "500M-1B EUR", "10B+ EUR").

        PRIORITY ORDER — rank by COMPLIANCE RELEVANCE, not by company size:
        1. Companies in HIGHLY REGULATED sub-sectors (financial services subsidiaries, chemicals, pharma, defense, critical infrastructure, energy)
        2. Companies facing IMMINENT regulatory deadlines or known compliance challenges
        3. Companies recently fined or under regulatory scrutiny
        4. Obvious major players that EVERYONE knows in this industry
        5. Hidden Champions — lesser-known but highly regulated mid-size firms (Mittelstand world market leaders, SDAX/MDAX-listed, specialized manufacturers subject to export controls, REACH, dual-use regulations, etc.)
        """
        let user = """
        Find exactly 25 real \(industry.rawValue) companies in \(region.countries).
        Requirements:
        - Revenue > 50M EUR or equivalent
        - 200+ employees
        - Currently active and operating
        - Include company website URL and LinkedIn company page URL
        - Include approximate number of employees as integer in the "employees" field (e.g. 250, 4500, 120000). This is MANDATORY.
        Return ALL 25 companies as a single JSON array. Do not truncate. Do not stop early. Count your results before returning - there must be 25 objects in the array.
        Example format: [{"name":"Example GmbH","industry":"...","region":"...","website":"https://...","linkedInURL":"https://...","description":"...","size":"large","country":"Germany","employees":2500}]
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 8000)
        return parseJSON(content).map { d in
            // Parse employees: try Int directly, then parse from String
            let employeeCount: Int = {
                if let intVal = Int(d["employees"] ?? "") {
                    return intVal
                }
                // Handle formatted numbers like "2,500" or "2.500"
                let cleaned = (d["employees"] ?? "")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(cleaned) ?? 0
            }()
            return Company(
                name: d["name"] ?? "Unknown",
                industry: d["industry"] ?? industry.rawValue,
                region: d["region"] ?? region.rawValue,
                website: d["website"] ?? "",
                linkedInURL: d["linkedInURL"] ?? "",
                description: d["description"] ?? "",
                size: d["size"] ?? "",
                country: d["country"] ?? "",
                employeeCount: employeeCount
            )
        }
    }

    // MARK: - 2) Ansprechpartner finden - Breite Suche ueber ALLE Quellen
    func findContacts(company: Company, apiKey: String) async throws -> [Lead] {
        let system1 = """
        You are a B2B research assistant. Search professional networks to find compliance, legal, regulatory, and risk management professionals.
        Return a JSON array. Each object: name, title, email, linkedInURL, phone, source, seniority_level.
        - name: Full name
        - title: Job title
        - email: Email if found, empty string if not
        - linkedInURL: LinkedIn or XING profile URL
        - phone: Phone if found, empty string if not
        - source: Where found (e.g. "LinkedIn", "XING", "theorg.com")
        - seniority_level: "C-Level", "VP", "Director", "Manager", "Other"
        IMPORTANT: Return ALL people found. Include compliance, legal, regulatory, data protection, risk management, GRC roles.
        """
        let user1 = """
        Find compliance and regulatory professionals at \(company.name).
        Industry: \(company.industry), Region: \(company.region), Website: \(company.website)
        Target roles:
        - Chief Compliance Officer (CCO), Head of Compliance, Compliance Manager/Director
        - VP/SVP Regulatory Affairs, Head of Regulatory
        - Data Protection Officer (DPO/DSB), Datenschutzbeauftragter
        - General Counsel, Chief Legal Officer, Head of Legal
        - Head of Risk / Chief Risk Officer (CRO)
        - Geldwäschebeauftragter (MLRO), AML Officer
        - Head of GRC, Information Security Officer (CISO)
        - Vorstand, Geschäftsführung with compliance responsibility
        Search LinkedIn profiles, XING profiles, theorg.com org charts for \(company.name).
        Return ALL found as JSON array.
        """
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
        var allCandidates = parseJSON(content1)

        if allCandidates.count < 3 {
            let system2 = """
            You are a research assistant. Search company websites, press releases, regulatory filings, annual reports, and conference speaker lists.
            Return a JSON array. Each object: name, title, email, linkedInURL, phone, source, seniority_level.
            Look at:
            - Company team/about/leadership/impressum pages
            - Press releases mentioning compliance or legal hires
            - Regulatory filings (BaFin, FCA, SEC registrations)
            - Annual reports and corporate governance sections
            - Conference speaker lists from compliance events
            - Handelsregister entries
            Return ALL people found.
            """
            let user2 = """
            Find compliance, legal, and regulatory professionals at \(company.name) (\(company.industry)).
            Website: \(company.website)
            Search the company website, especially team/about/impressum/leadership pages.
            Search press releases about \(company.name) compliance hires.
            Search regulatory registrations and filings mentioning \(company.name).
            Search annual reports and corporate governance documents.
            Also search for: Vorstand, Geschäftsführung, C-Level executives at \(company.name).
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
        You are an expert at finding verified business email addresses from email databases and contact platforms.
        Search EXHAUSTIVELY across:
        1. Hunter.io - email finder and verifier
        2. ZoomInfo - contact database
        3. Apollo.io - B2B contact data
        4. RocketReach - professional emails
        5. Lusha - business contact info
        6. SignalHire - professional contact data
        7. Clearbit - company data
        8. Kaspr - LinkedIn email finder
        Return JSON:
        - emails: [{email, source, confidence}] where confidence = "high"/"medium"/"low"
        - company_email_pattern: the naming convention (e.g. "firstname.lastname@domain.com")
        - pattern_examples: other verified emails at this company
        - company_domain: the company's primary email domain
        - notes: additional context
        """
        let user1 = """
        Find the business email for:
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company)
        Known email (may be wrong): \(lead.email)
        LinkedIn: \(lead.linkedInURL)
        Search Hunter.io, ZoomInfo, Apollo, RocketReach, Lusha, SignalHire for this person's email.
        Also find the company email pattern by looking at other employees' emails.
        Return JSON.
        """
        do {
            let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
            let json1 = cleanJSON(content1)
            if let data = json1.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let emails = dict["emails"] as? [[String: Any]] {
                    for e in emails {
                        if let addr = e["email"] as? String, !addr.isEmpty, addr.contains("@") {
                            allEmails.append((email: addr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), source: e["source"] as? String ?? "Email DB", confidence: e["confidence"] as? String ?? "medium"))
                        }
                    }
                }
                if let pattern = dict["company_email_pattern"] as? String, !pattern.isEmpty { allNotes.append("Pattern: \(pattern)") }
                if let cd = dict["company_domain"] as? String, !cd.isEmpty { allNotes.append("Domain: \(cd)") }
                if let notes = dict["notes"] as? String, !notes.isEmpty { allNotes.append(notes) }
            }
        } catch { allNotes.append("Pass 1 (email DBs): \(error.localizedDescription)") }

        let system2 = """
        You are an email verification specialist with deep analytical capabilities.
        Given a person, candidate emails, and company email patterns, determine the most likely correct email.
        Analyze:
        1. Does the email follow the company's naming pattern?
        2. Is the domain correct for this company?
        3. Cross-reference with multiple sources
        4. Check for common email patterns (firstname.lastname, f.lastname, first.last, etc.)
        Return JSON: {best_email, verified (bool), confidence, verification_sources, alternative_emails, reasoning}
        """
        let candidateEmails = allEmails.map { $0.email }.prefix(8).joined(separator: ", ")
        let patternStr = allNotes.prefix(3).joined(separator: " | ")
        let user2 = """
        Verify the best email for:
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company)
        LinkedIn: \(lead.linkedInURL)
        Candidate emails: \(candidateEmails.isEmpty ? "none found" : candidateEmails)
        Known patterns: \(patternStr.isEmpty ? "no patterns found" : patternStr)
        Analyze all candidates. Which is most likely correct? Cross-verify across sources.
        Return JSON with best_email, verified, confidence, reasoning.
        """
        do {
            let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 3000, model: modelReasoning)
            let json2 = cleanJSON(content2)
            if let data = json2.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let bestEmail = dict["best_email"] as? String, !bestEmail.isEmpty, bestEmail.contains("@") {
                    let conf = dict["confidence"] as? String ?? "medium"
                    let verified = dict["verified"] as? Bool ?? false
                    allEmails.insert((email: bestEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), source: "Cross-verification (Reasoning)", confidence: verified ? "high" : conf), at: 0)
                }
                if let alts = dict["alternative_emails"] as? [String] {
                    for alt in alts where alt.contains("@") && !alt.isEmpty {
                        let cleanAlt = alt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !allEmails.contains(where: { $0.email == cleanAlt }) {
                            allEmails.append((email: cleanAlt, source: "Alternative", confidence: "low"))
                        }
                    }
                }
                if let reasoning = dict["reasoning"] as? String, !reasoning.isEmpty { allNotes.append("Reasoning: \(reasoning)") }
            }
        } catch { allNotes.append("Pass 2 (reasoning): \(error.localizedDescription)") }

        let uniqueEmails = Dictionary(grouping: allEmails, by: { $0.email })
        let best = allEmails.first(where: { $0.confidence == "high" })
            ?? allEmails.first(where: { $0.confidence == "medium" && (uniqueEmails[$0.email]?.count ?? 0) > 1 })
            ?? allEmails.first(where: { $0.confidence == "medium" })
            ?? allEmails.first
        let finalEmail = best?.email ?? lead.email
        let isVerified = best?.confidence == "high"
            || (best != nil && (uniqueEmails[best!.email]?.count ?? 0) > 1)
            || best?.confidence == "medium"

        var notesParts: [String] = []
        if let b = best {
            notesParts.append("Best: \(b.email) (\(b.source), \(b.confidence))")
        } else {
            notesParts.append("No email found")
        }
        notesParts.append("Candidates: \(allEmails.count), Sources: \(Set(allEmails.map { $0.source }).count)")
        notesParts.append(contentsOf: allNotes.prefix(5))
        let notes = notesParts.joined(separator: " | ")

        return (
            email: cleanEmail(finalEmail.isEmpty ? lead.email : finalEmail),
            verified: isVerified,
            notes: String(notes.prefix(500))
        )
    }

    // MARK: - 4) Branchen-Challenges recherchieren (EU-focused, with fallback)
    func researchChallenges(company: Company, apiKey: String) async throws -> String {
        let system = """
        Du bist ein Regulatory-Compliance-Experte mit tiefem Wissen über EU-Regulierung.
        Recherchiere KONKRETE, AKTUELLE regulatorische Herausforderungen für \(company.name).

        KRITISCHE REGELN:
        - Recherchiere NUR über \(company.name) selbst — keine anderen Unternehmen.
        - Nenne NUR Regulierungen, die TATSÄCHLICH für \(company.name) in der Branche \(company.industry) gelten.
        - Nutze ECHTE, VERIFIZIERBARE Fakten: konkrete Fristen, Bußgelder, Artikelnummern, aktuelle Fälle.
        - KEINE erfundenen Referenzen, Konferenzen, Artikel oder Events.
        - Wenn du etwas nicht sicher weißt, lass es weg statt es zu erfinden.
        - Antworte auf Englisch.

        Struktur deiner Antwort:
        1. Welche EU/nationale Regulierungen gelten DIREKT für \(company.name)? (z.B. DORA, NIS2, GDPR, CSRD, EU AI Act, MiCA, PSD2, AML6)
        2. Nächste konkrete Compliance-Fristen für \(company.name)
        3. Aktuelle Bußgelder oder Enforcement-Aktionen in deren Sektor
        4. Typische Compliance-Lücken für Unternehmen wie \(company.name)
        """
        let user = """
        Recherchiere die wichtigsten regulatorischen Compliance-Herausforderungen für \(company.name) (Branche: \(company.industry)).

        Ich brauche SPEZIFISCHE, VERIFIZIERBARE Informationen über dieses Unternehmen:
        - Welche konkreten EU-Regulierungen betreffen \(company.name)?
        - Welche Fristen stehen an?
        - Gab es kürzlich Bußgelder oder behördliche Maßnahmen in deren Sektor?
        - Welche Compliance-Lücken sind typisch für Unternehmen dieser Art?

        Suche bei Regulierungsbehörden (BaFin, EBA, ESMA, FCA), aktuellen Nachrichten, Compliance-Berichten.
        Nenne konkrete Daten, Beträge und Regulierungsartikel. Antworte auf Englisch.

        WICHTIG: Erfinde NICHTS. Nur verifizierbare Fakten.
        """
        let raw = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 4000, model: modelReasoning)

        // Apply unknown-company fallback, mirroring the Python logic
        if Self.isUnknownCompany(raw) {
            return Self.genericComplianceChallenges(companyName: company.name, industry: company.industry)
        }
        return raw
    }

    // MARK: - 5) Personalisierte Email erstellen - ALWAYS IN ENGLISH
    func draftEmail(lead: Lead, challenges: String, senderName: String, apiKey: String) async throws -> OutboundEmail {
        // Trim challenges to avoid token overflow — keep essential info
        let challengesTrimmed = challenges.isEmpty ? "No specific challenges researched." : String(challenges.prefix(2000))

        let system = """
        Du schreibst professionelle B2B-Outreach-E-Mails für Harpocrates Corp / comply.reg.

        KRITISCHE REGELN:
        1. Schreibe die E-Mail auf ENGLISCH.
        2. Der Betreff MUSS den Firmennamen "\(lead.company)" enthalten und sich auf eine KONKRETE Regulierung beziehen, die für \(lead.company) relevant ist (z.B. DORA, NIS2, CSRD, GDPR).
        3. Die E-Mail muss KLAR und VERSTÄNDLICH sein — ein Compliance-Manager muss sofort verstehen, worum es geht.
        4. KEINE erfundenen Referenzen: Keine erfundenen Artikel, Konferenzen, Reports, Zitate oder Events wie "Money20/20". Wenn du etwas nicht verifizieren kannst, erwähne es NICHT.
        5. KEINE Marketing-Phrasen wie "caught in the exact squeeze", "pulling real-time regulatory updates", oder ähnlichen Jargon.
        6. STRUKTUR der E-Mail:
           - Zeile 1-2: Konkret sagen, WARUM du dich an diese Person wendest (welche Regulierung betrifft \(lead.company))
           - Zeile 3-5: Wie comply.reg KONKRET bei diesem spezifischen Problem hilft
           - Letzte Zeile: Höfliche Frage nach einem kurzen Gespräch (15 Min)
        7. Maximal 120 Wörter. Jeder Satz muss einen klaren Zweck haben.
        8. Absender: \(senderName), Harpocrates Corp
        9. KEINE Signatur oder Footer — wird automatisch hinzugefügt.
        10. Die E-Mail muss KOMPLETT sein — nicht abschneiden.
        11. Alle Währungsangaben in EUR.
        12. Wenn Quellen angegeben werden, nur echte, verifizierbare URLs.

        ÜBER COMPLY.REG:
        comply.reg ist eine RegTech-SaaS-Plattform für automatisiertes Compliance-Monitoring:
        - Automatische Erkennung regulatorischer Änderungen (DORA, NIS2, GDPR, CSRD, EU AI Act, MiCA, AML)
        - Echtzeit-Überwachung von Compliance-Anforderungen
        - Automatische Gap-Analyse und Risikobewertung
        - Zentrale Verwaltung aller Compliance-Pflichten

        Return ONLY valid JSON: {"subject": "...", "body": "..."}
        """
        let user = """
        Schreibe eine Outreach-E-Mail von \(senderName) (Harpocrates Corp) an:
        Name: \(lead.name)
        Position: \(lead.title)
        Unternehmen: \(lead.company)

        RECHERCHIERTE REGULATORISCHE HERAUSFORDERUNGEN FÜR \(lead.company):
        \(challengesTrimmed)

        ANWEISUNGEN:
        - Der Betreff MUSS "\(lead.company)" enthalten
        - Beziehe dich auf 1-2 KONKRETE Regulierungen, die \(lead.company) betreffen
        - Erkläre klar, wie comply.reg bei genau diesem Problem hilft
        - Maximal 120 Wörter
        - E-Mail muss KOMPLETT sein (vollständiger Text, nicht abgeschnitten)
        - KEINE erfundenen Events, Artikel oder Konferenzen
        - Schreibe auf Englisch
        - Alle Währungen in EUR

        Return ONLY valid JSON: {"subject": "...", "body": "..."}
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 3000)
        let json = cleanJSON(content)

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Regulatory Compliance for \(lead.company)", body: stripCitations(content))
        }

        var rawBody = dict["body"] as? String ?? content
        if rawBody.isEmpty { rawBody = content }
        var rawSubject = dict["subject"] as? String ?? ""
        if rawSubject.isEmpty { rawSubject = "Regulatory Compliance for \(lead.company)" }

        // Ensure subject always contains the company name
        if !rawSubject.lowercased().contains(lead.company.lowercased()) {
            rawSubject = "\(rawSubject) — \(lead.company)"
        }

        return OutboundEmail(
            subject: stripCitations(rawSubject),
            body: stripCitations(rawBody)
        )
    }

    // MARK: - 6) Follow-up Email erstellen - ALWAYS IN ENGLISH
    func draftFollowUp(lead: Lead, originalEmail: String, followUpEmail: String = "", replyReceived: String = "", senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = """
        You write professional follow-up emails for B2B outreach. CRITICAL RULES:
        1. ALWAYS write in English.
        2. Based on previous emails and any replies, write a follow-up that:
           - References the previous conversation naturally
           - If reply: acknowledge and continue dialogue
           - If no reply: use a FRESH ANGLE with new value (recent event, new insight)
           - Under 150 words, professional, value-focused
           - Do NOT repeat the same pitch
        3. Make content specifically relevant to the recipient.
        Return ONLY valid JSON: {subject, body}
        """
        var ctx = "Previous email to \(lead.name) at \(lead.company):\n\(originalEmail)"
        if !followUpEmail.isEmpty { ctx += "\n\nPrevious follow-up:\n\(followUpEmail)" }
        if !replyReceived.isEmpty { ctx += "\n\nReply from \(lead.name):\n\(replyReceived)" }

        let user = """
        Write a follow-up from \(senderName) at Harpocrates Corp.
        CONVERSATION HISTORY:
        \(ctx)

        Write the next follow-up in English. If a reply was received, respond directly. If no reply, bring new value.
        Return JSON: {subject, body}
        """
        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 2000, model: modelReasoning)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OutboundEmail(subject: "Following up - \(lead.company)", body: stripCitations(content))
        }
        let rawBody2 = dict["body"] as? String ?? content
        return OutboundEmail(
            subject: dict["subject"] as? String ?? "Following up - \(lead.company)",
            body: stripCitations(rawBody2)
        )
    }

    // MARK: - 7) Social Post generieren - LinkedIn ONLY, EU-focused, with real sources
    func generateSocialPost(
        topic: ContentTopic,
        platform: SocialPlatform,
        industries: [String],
        existingPosts: [SocialPost] = [],
        apiKey: String
    ) async throws -> SocialPost {
        // Deduplication: pass existing post titles/previews to the prompt
        let existingTitles = existingPosts.prefix(10).map { String($0.content.prefix(80)) }
        let dupeContext: String
        if existingTitles.isEmpty {
            dupeContext = ""
        } else {
            dupeContext = "\n\nALREADY POSTED (DO NOT REPEAT):\n- " + existingTitles.joined(separator: "\n- ")
        }

        // Current timestamp for the post
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        let timestamp = formatter.string(from: Date())

        let system = """
        You are a social media expert for Harpocrates Corp and comply.reg.
        comply.reg: RegTech SaaS for automated compliance monitoring, regulatory change management, risk assessment.

        MANDATORY RULES:
        1. PLATFORM: Write for LinkedIn ONLY. No Twitter/X content.
        2. LANGUAGE: Write ENTIRELY in English with CORRECT capitalisation (proper nouns, sentence beginnings, acronyms). This is an official corporate post — do NOT write in all-lowercase.
        3. GEOGRAPHIC FOCUS: ALL content MUST focus on EUROPE (EU, EEA, UK, Switzerland). Do NOT reference US, SEC, or non-European regulators unless comparing to EU rules.
        4. CURRENCY: ALL monetary values MUST be in EUR (€). Convert any USD or GBP figures to EUR.
        5. FACTS: Every post MUST have 1-2 concrete numbers/statistics with explicit source citation in the text (e.g. "According to EBA's 2025 Annual Report", "Source: European Commission, \(timestamp)"). Raw numbers without sources are NOT acceptable.
        6. SOURCES: Include real, clickable URLs where possible. Sources must be real and verifiable — no invented publications, conferences, or events.
        7. NO HALLUCINATIONS: Only verifiable facts from real European regulatory bodies, institutions, or reputable publications.
        8. COMPLY.REG RELEVANCE: Address problems comply.reg solves.
        9. NO DUPLICATE topic/hook. Study the ALREADY POSTED list carefully — use DIFFERENT angles, statistics, regulations, and hooks.
        10. FOOTER: Added automatically — do NOT include any footer in the content.
        11. VALUE: Genuine insight for European compliance professionals.
        12. TIMELINESS: Reference recent EU regulatory developments (current date: \(timestamp)), ECB/EBA/ESMA/BaFin publications.
        13. EUROPEAN REGULATIONS ONLY: Focus on DORA, NIS2, GDPR, MiCA, CSRD, EU AI Act, PSD2/PSD3, AML6/AMLD, EBA Guidelines, Lieferkettengesetz/CSDDD.
        14. CAPITALISATION: Use STANDARD English capitalisation. Capitalise: first word of each sentence, proper nouns (European Commission, BaFin, DORA), acronyms, titles. Do NOT write everything in lowercase.
        Return JSON: {"content": "...", "hashtags": [...], "sources": ["Source Name (URL)"]}
        """

        let industryContext = industries.isEmpty ? "Financial Services, RegTech, Compliance" : industries.joined(separator: ", ")
        let user = """
        Write a LinkedIn post for Harpocrates Corp / comply.reg.
        Topic: \(topic.rawValue) - \(topic.promptPrefix) \(industryContext)
        Date: \(timestamp)

        REQUIREMENTS:
        - Write in English with CORRECT capitalisation (this is a professional corporate post, NOT casual text)
        - ALL content focused on EUROPE (EU, EEA, UK, Switzerland) — no US/SEC references
        - ALL monetary amounts in EUR (€)
        - Hook in line 1 (number or provocative thesis)
        - At least 1-2 concrete numbers/statistics, each with EXPLICIT SOURCE ATTRIBUTION in the text (e.g. "According to [Source], ...")
        - Reference DORA, NIS2, GDPR, MiCA, EU AI Act, CSRD, PSD3, AMLD, EBA Guidelines or current EU regulations
        - Include the specific source name and date for each claim; prefer real URLs
        - Question or CTA at end
        - Mention comply.reg naturally
        - 150-250 words, line breaks\(dupeContext)
        Hashtags: 5-7 from: #DORA #NIS2 #GDPR #RegTech #Compliance #FinTech #RegulatoryCompliance #comply #RiskManagement #AML #BaFin #EBA #ESMA #ECB #CSRD #EUAIAct
        Return ONLY valid JSON with content, hashtags, AND sources array.
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 3000, model: modelReasoning)
        let json = cleanJSON(content)

        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SocialPost(platform: .linkedin, content: Self.ensureFooter(stripCitations(content)))
        }

        let rawContent = dict["content"] as? String ?? content
        let hashtags = (dict["hashtags"] as? [String]) ?? []
        let postSources = (dict["sources"] as? [String]) ?? []

        let hashtagLine = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        var fullContent = Self.stripTrailingHashtags(rawContent)

        // Append real source URLs if provided
        let realURLs = postSources.filter { $0.contains("http") }
        if !realURLs.isEmpty {
            let sourceLines = realURLs.prefix(5).map { "• \($0)" }.joined(separator: "\n")
            fullContent += "\n\nSources:\n" + sourceLines
        }

        if !hashtagLine.isEmpty { fullContent += "\n\n" + hashtagLine }
        fullContent = Self.ensureFooter(fullContent)

        // Always return LinkedIn platform regardless of what was passed in
        return SocialPost(platform: .linkedin, content: fullContent, hashtags: hashtags)
    }

    // MARK: - 8) Dynamic Subject Line Generation
    func generateSubjectAlternatives(company: Company, emailBody: String, apiKey: String) async throws -> [String] {
        let systemPrompt = """
        Generiere genau 3 verschiedene E-Mail-Betreffzeilen für RegTech/Compliance-Outreach.
        Jede Betreffzeile MUSS:
        - Den Firmennamen "\(company.name)" enthalten
        - Sich auf eine KONKRETE Regulierung beziehen (DORA, NIS2, CSRD, GDPR, EU AI Act, etc.)
        - Maximal 70 Zeichen lang sein
        - Auf Englisch sein
        - NICHT generisch oder spammig klingen
        Return ONLY 3 lines. No numbering, no quotes, no explanation.
        """
        let userPrompt = """
        Company: \(company.name)
        Industry: \(company.industry)
        Email context: \(String(emailBody.prefix(300)))
        Generate 3 subject lines. Each MUST contain "\(company.name)".
        """

        let content = try await callAPI(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey, maxTokens: 200)

        // Parse and clean the raw lines
        var subjects = content
            .components(separatedBy: "\n")
            .map { $0
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty && $0.count > 5 && $0.count < 100 }
            // Strip leading numbering like "1. " or "1) "
            .map { line -> String in
                var s = line
                if s.count > 3, s[s.startIndex].isNumber {
                    let prefixes = [". ", ") ", "- "]
                    for sep in prefixes {
                        if let r = s.range(of: sep), s.distance(from: s.startIndex, to: r.lowerBound) <= 2 {
                            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
                return s
            }

        // Ensure company name appears in every subject
        subjects = subjects.map { s in
            if s.lowercased().contains(company.name.lowercased()) {
                return s
            }
            return "\(s) — \(company.name)"
        }

        return Array(subjects.prefix(3)).isEmpty
            ? ["Regulatory Compliance for \(company.name)"]
            : Array(subjects.prefix(3))
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
        // Strip <think>...</think> blocks from reasoning models
        if let thinkRange = s.range(of: "</think>") {
            s = String(s[thinkRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
