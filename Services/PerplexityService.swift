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
        
        Return ALL 25 companies as a single JSON array. Do not truncate. Do not stop early.
        Count your results before returning - there must be 25 objects in the array.
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
        - theorg.com organizational charts
        
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
        
        Search LinkedIn, \(company.website), theorg.com, business directories, press releases, XING, annual reports.
        Return ALL people you find as JSON array.
        """
        
        let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
        var allCandidates = parseJSON(content1)
        
        // Schritt 2: Falls wenig Ergebnisse, zweite Suche mit anderen Suchtermen
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
    
    // MARK: - 3) Email verifizieren - Multi-Pass Maximale Quellensuche
    func verifyEmail(lead: Lead, apiKey: String) async throws -> (email: String, verified: Bool, notes: String) {
        var allEmails: [(email: String, source: String, confidence: String)] = []
        var allNotes: [String] = []
        
        // === PASS 1: Exhaustive Quellensuche ===
        let system1 = """
        You are an expert at finding verified business email addresses from public sources.
        Search EXHAUSTIVELY across ALL of these sources - take your time, accuracy matters more than speed:
        
        1. LinkedIn - profile page, contact info section, activity posts, comments
        2. Company website - team page, about us, leadership, impressum, Kontakt, press/news section
        3. theorg.com - search for the company's organizational chart and contact details
        4. XING profiles (critical for DACH region companies)
        5. Business directories: ZoomInfo, Apollo.io, Lusha, RocketReach, Hunter.io
        6. Financial databases: Bloomberg, Reuters, Crunchbase
        7. Press releases and news articles mentioning this person with contact info
        8. Conference and event speaker listings with contact details
        9. Academic publications, papers, or presentations
        10. Regulatory filings (BaFin, SEC, Handelsregister, Bundesanzeiger)
        11. Social media: Twitter/X bio, GitHub profile, personal websites/blogs
        12. Industry association member directories
        13. Patent filings and legal documents
        14. Google search: "firstname lastname email company"
        15. Company annual reports and governance documents
        16. Podcast appearances or webinar registrations
        17. Job posting contact information
        
        Return a JSON object with:
        - emails: array of objects, each with {email, source, confidence} where confidence is "high", "medium", or "low"
        - company_email_pattern: the naming pattern used at this company (e.g. "firstname.lastname@company.com", "f.lastname@company.com")
        - pattern_examples: array of other verified emails at the same company that prove the pattern
        - notes: string with additional context about your findings
        
        IMPORTANT RULES:
        - Search ALL sources listed above, not just a few
        - "high" confidence = email found directly in a verified source (company website, press release, etc.)
        - "medium" confidence = email constructed from verified company pattern with 2+ examples
        - "low" confidence = educated guess or single-source finding
        - If you find the company email pattern from other employees, construct the likely email for this person
        - Return ALL email variants you find, even duplicates from different sources (helps verify)
        """
        let user1 = """
        Find the business email address for this person - search ALL available sources:
        
        Name: \(lead.name)
        Title: \(lead.title)
        Company: \(lead.company)
        Current email (may be empty or wrong): \(lead.email)
        LinkedIn: \(lead.linkedInURL)
        
        SEARCH STRATEGY:
        1. First search theorg.com for "\(lead.company)" org chart - often has direct contact info
        2. Search LinkedIn for "\(lead.name)" at "\(lead.company)"
        3. Check \(lead.company) website team/impressum/contact pages
        4. Search XING for "\(lead.name)"
        5. Search ZoomInfo, Apollo.io, RocketReach, Lusha for "\(lead.name)" at "\(lead.company)"
        6. Search Hunter.io for email patterns at the company domain
        7. Google: "\(lead.name)" "\(lead.company)" "email" OR "@"
        8. Check Handelsregister/Bundesanzeiger if German company
        9. Search press releases: "\(lead.name)" "\(lead.company)"
        10. Check conference speaker lists for "\(lead.name)"
        
        Return ALL findings as JSON. Every source matters.
        """
        
        do {
            let content1 = try await callAPI(systemPrompt: system1, userPrompt: user1, apiKey: apiKey, maxTokens: 4000)
            let json1 = cleanJSON(content1)
            if let data = json1.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let emails = dict["emails"] as? [[String: Any]] {
                    for e in emails {
                        if let addr = e["email"] as? String, !addr.isEmpty, addr.contains("@") {
                            allEmails.append((
                                email: addr.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                                source: e["source"] as? String ?? "Search",
                                confidence: e["confidence"] as? String ?? "medium"
                            ))
                        }
                    }
                }
                if let pattern = dict["company_email_pattern"] as? String, !pattern.isEmpty {
                    allNotes.append("Pattern: \(pattern)")
                }
                if let examples = dict["pattern_examples"] as? [String], !examples.isEmpty {
                    allNotes.append("Pattern examples: \(examples.prefix(3).joined(separator: ", "))")
                }
                if let notes = dict["notes"] as? String, !notes.isEmpty {
                    allNotes.append(notes)
                }
            }
        } catch {
            allNotes.append("Pass 1: \(error.localizedDescription)")
        }
        
        // === PASS 2: Cross-Verification und Pattern-Matching ===
        let system2 = """
        You are an email verification specialist. Your job is to VERIFY and CROSS-CHECK email addresses.
        
        Given a person and candidate emails, verify them by:
        1. Checking if the email domain matches the company's actual domain
        2. Finding the company's email naming convention from other employees
        3. Cross-referencing with theorg.com, Hunter.io patterns, and other sources
        4. Searching for the specific email address in public sources to confirm it exists
        5. Checking MX records and common email patterns for the domain
        
        Return JSON with:
        - best_email: the single most likely correct email address
        - verified: boolean - true if you found direct evidence this email is real
        - confidence: "high", "medium", or "low"
        - verification_sources: array of sources that confirm this email
        - alternative_emails: array of other possible email addresses
        - reasoning: brief explanation of why you chose this email
        """
        let candidateEmails = allEmails.map { $0.email }.prefix(5).joined(separator: ", ")
        let user2 = """
        Verify the best email for:
        Person: \(lead.name), \(lead.title) at \(lead.company)
        LinkedIn: \(lead.linkedInURL)
        
        Candidate emails found so far: \(candidateEmails.isEmpty ? "none found yet" : candidateEmails)
        
        VERIFICATION STEPS:
        1. Search theorg.com for \(lead.company) - check org chart for this person's contact
        2. Find 3+ other employee emails at \(lead.company) to determine the naming pattern
        3. If candidates exist, verify them against the pattern
        4. If no candidates, construct the most likely email from the verified pattern
        5. Search Google for the constructed email to see if it appears anywhere
        6. Check if the email domain has MX records (is a valid email domain)
        
        Return your verification result as JSON.
        """
        
        do {
            let content2 = try await callAPI(systemPrompt: system2, userPrompt: user2, apiKey: apiKey, maxTokens: 3000)
            let json2 = cleanJSON(content2)
            if let data = json2.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let bestEmail = dict["best_email"] as? String, !bestEmail.isEmpty, bestEmail.contains("@") {
                    let conf = dict["confidence"] as? String ?? "medium"
                    let verified = dict["verified"] as? Bool ?? false
                    allEmails.insert((
                        email: bestEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                        source: "Cross-verification",
                        confidence: verified ? "high" : conf
                    ), at: 0)
                }
                if let alts = dict["alternative_emails"] as? [String] {
                    for alt in alts where alt.contains("@") && !alt.isEmpty {
                        let cleanAlt = alt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !allEmails.contains(where: { $0.email == cleanAlt }) {
                            allEmails.append((email: cleanAlt, source: "Alternative", confidence: "low"))
                        }
                    }
                }
                if let sources = dict["verification_sources"] as? [String], !sources.isEmpty {
                    allNotes.append("Verified via: \(sources.joined(separator: ", "))")
                }
                if let reasoning = dict["reasoning"] as? String, !reasoning.isEmpty {
                    allNotes.append(reasoning)
                }
            }
        } catch {
            allNotes.append("Pass 2: \(error.localizedDescription)")
        }
        
        // === Beste Email auswaehlen ===
        // Prioritaet: high confidence > medium > low
        // Bei gleicher Konfidenz: Email die in mehreren Quellen auftaucht
        let uniqueEmails = Dictionary(grouping: allEmails, by: { $0.email })
        
        let best = allEmails.first(where: { $0.confidence == "high" })
            ?? allEmails.first(where: { $0.confidence == "medium" && (uniqueEmails[$0.email]?.count ?? 0) > 1 })
            ?? allEmails.first(where: { $0.confidence == "medium" })
            ?? allEmails.first
        
        let finalEmail = best?.email ?? lead.email
        let isVerified = best?.confidence == "high"
            || (best != nil && (uniqueEmails[best!.email]?.count ?? 0) > 1)
                    || best?.confidence == "medium"
        
        let summaryParts = [
            best.map { "Best: \($0.email) (\($0.source), \($0.confidence) confidence)" } ?? "No email found",
            "Total candidates: \(allEmails.count)"
        ] + allNotes
        let notes = summaryParts.joined(separator: " | ")
        
        return (
            email: cleanEmail(finalEmail.isEmpty ? lead.email : finalEmail),
            verified: isVerified,
            notes: String(notes.prefix(500))
        )
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
    
    // MARK: - 6) Follow-up Email erstellen (mit Konversationshistorie)
    func draftFollowUp(lead: Lead, originalEmail: String, followUpEmail: String = "", replyReceived: String = "", senderName: String, apiKey: String) async throws -> OutboundEmail {
        let system = """
        You write professional follow-up emails for B2B outreach. You have access to the full conversation history.
        Based on the previous emails and any replies received, write a follow-up that:
        - References the previous conversation naturally
        - If there was a reply: acknowledge it and continue the dialogue
        - If there was no reply: add new value and a different angle
        - Summarizes key points from previous emails briefly
        - Keeps it under 150 words, professional, value-focused
        - Do NOT repeat the same pitch. Bring fresh insights.
        Return ONLY a valid JSON object with: subject, body
        """
        var conversationContext = "Previous email sent to \(lead.name) at \(lead.company):\n\(originalEmail)"
        if !followUpEmail.isEmpty {
            conversationContext += "\n\nPrevious follow-up sent:\n\(followUpEmail)"
        }
        if !replyReceived.isEmpty {
            conversationContext += "\n\nReply received from \(lead.name):\n\(replyReceived)"
        }
        let user = """
        Write a follow-up email from \(senderName) at Harpocrates Corp.
        
        CONVERSATION HISTORY:
        \(conversationContext)
        
        Based on the above conversation, write the next follow-up email.
        If a reply was received, respond to it directly.
        If no reply was received, try a different angle to provide value.
        
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
    
    // MARK: - 8) Social Post generieren (comply.reg-fokussiert + Quellen + Duplicate-Check)
    func generateSocialPost(topic: ContentTopic, platform: SocialPlatform, industries: [String], existingPosts: [SocialPost] = [], apiKey: String) async throws -> SocialPost {
        // Bereits gepostete Inhalte als Kontext (Duplicate-Prevention)
        let existingTitles = existingPosts.prefix(10).map { String($0.content.prefix(80)) }.joined(separator: "\n- ")
        let dupeContext = existingPosts.isEmpty ? "" : "\n\nBEREITS GEPOSTETE INHALTE (NICHT WIEDERHOLEN):\n- " + existingTitles

        let system = """
        Du bist Social-Media-Experte fuer Harpocrates Corp und das Produkt comply.reg.
        comply.reg ist eine RegTech SaaS-Plattform fuer automatisiertes Compliance-Monitoring,
        Regulatory Change Management und Risikobewertung fuer Fintech, Banken und regulierte Unternehmen.

        PFLICHTREGELN fuer jeden Post:
        1. FAKTEN & ZAHLEN: Jeder Post MUSS mindestens 1-2 konkrete Zahlen, Statistiken oder Daten enthalten
           (z.B. Bussgelder bis 10 Mio EUR, 72h-Meldepflicht, DORA gilt ab 17.01.2025)
        2. QUELLENANGABE: Zahlen und Fakten MUESSEN mit Quelle zitiert werden
           Format: (Quelle: EBA, BaFin, EZB, ESMA, EU-Amtsblatt, etc.)
        3. KEINE HALLUZINATIONEN: Nur belegbare Fakten verwenden. Bei Unsicherheit: keine spezifische Zahl.
        4. COMPLY.REG RELEVANZ: Post muss auf Probleme eingehen die comply.reg loest.
        5. KEIN DUPLICATE: Thema und Hook muessen sich von bereits geposteten Inhalten unterscheiden.

        Return JSON: {"content": "...", "hashtags": [...]}
        """

        let industryContext = industries.isEmpty ? "Finanzdienstleistungen, RegTech, Compliance" : industries.joined(separator: ", ")
        let user = """
        Schreibe einen \(platform.rawValue)-Post fuer Harpocrates Corp / comply.reg.
        Thema: \(topic.rawValue) - \(topic.promptPrefix) \(industryContext)

        ANFORDERUNGEN:
        - Hook in Zeile 1 (Zahl oder provokante These)
        - Mindestens 1 konkrete Zahl/Statistik mit Quelle in Klammern
        - Bezug zu DORA, NIS2, DSGVO, MiCA, EU AI Act, CSRD oder aktuellen EU-Regularien
        - Frage oder CTA am Ende
        - comply.reg natuerlich erwaehnen (kein Hard-Sell)
        - LinkedIn: 150-250 Woerter, Zeilenumbrueche fuer Lesbarkeit\(dupeContext)

        Hashtags: 5-7 aus: #DORA #NIS2 #DSGVO #RegTech #Compliance #FinTech #RegulatoryCompliance #comply #RiskManagement #AML #BaFin #EBA

        Return ONLY valid JSON: {"content": "...", "hashtags": [...]}
        """

        let content = try await callAPI(systemPrompt: system, userPrompt: user, apiKey: apiKey, maxTokens: 2000)
        let json = cleanJSON(content)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: Content + Footer
                              return SocialPost(platform: platform, content: Self.ensureFooter(content))
        }
        
        // Kompletten Post zusammenbauen: Content (ohne doppelte Hashtags) + Hashtags + Footer
        let rawContent = dict["content"] as? String ?? content
        let hashtags = (dict["hashtags"] as? [String]) ?? []
        let hashtagLine = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        
        var fullContent = Self.stripTrailingHashtags(rawContent)
        if !hashtagLine.isEmpty {
            fullContent += "\n\n" + hashtagLine
        }
        fullContent = Self.ensureFooter(fullContent)
        
        return SocialPost(
            platform: platform,
            content: fullContent,
            hashtags: hashtags
        )
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
