# Code-Patches fuer LinkedIn Post + Content Qualitaet

## 1. PerplexityService.swift - generateSocialPost ersetzen (Zeile ~525-561)

Die GESAMTE `func generateSocialPost(...)` Funktion loeschen und durch folgende ersetzen:

```swift
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
            return SocialPost(platform: platform, content: content)
        }
        let hashtags = (dict["hashtags"] as? [String]) ?? []
        return SocialPost(
            platform: platform,
            content: dict["content"] as? String ?? content,
            hashtags: hashtags
        )
    }
```

## 2. ContentGenerationView.swift - publishToLinkedIn ersetzen

In der `publishToLinkedIn()` Funktion den GESAMTEN Inhalt ersetzen durch:

```swift
    private func publishToLinkedIn() {
        guard let post = generatedSocialPost else { return }

        // Text zusammenbauen
        let hashtags = post.hashtags.map { "#\($0)" }.joined(separator: " ")
        let fullText = post.hashtags.isEmpty ? post.content : "\(post.content)\n\n\(hashtags)"

        // LinkedIn Share-URL im Browser oeffnen
        var components = URLComponents(string: "https://www.linkedin.com/shareArticle")
        components?.queryItems = [
            URLQueryItem(name: "mini", value: "true"),
            URLQueryItem(name: "summary", value: fullText)
        ]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }

        // Status aktualisieren
        viewModel.socialPosts.append(post)
    }
```

Dazu `import AppKit` am Anfang der Datei hinzufuegen (falls noch nicht vorhanden).

## 3. ContentGenerationView.swift - generateLinkedInPost Aufruf aendern

In `generateLinkedInPost()` den Aufruf aendern von:
```swift
let post = try await viewModel.perplexityService.generateSocialPost(
    topic: selectedTopic,
    platform: .linkedIn,
    industries: [],
    apiKey: viewModel.settings.perplexityAPIKey
)
```

Zu:
```swift
let post = try await viewModel.perplexityService.generateSocialPost(
    topic: selectedTopic,
    platform: .linkedIn,
    industries: [],
    existingPosts: viewModel.socialPosts,
    apiKey: viewModel.settings.perplexityAPIKey
)
```

## Zusammenfassung der Aenderungen

| Datei | Aenderung | Grund |
|---|---|---|
| PerplexityService.swift | Neuer generateSocialPost mit comply.reg Prompt + existingPosts Parameter | Harpocrates-fokussiert, Quellen-Pflicht, Duplicate-Check |
| ContentGenerationView.swift | publishToLinkedIn -> Browser Share statt API Post | User hat Kontrolle ueber LinkedIn |
| ContentGenerationView.swift | import AppKit hinzufuegen | NSWorkspace.shared.open braucht AppKit |
| ContentGenerationView.swift | existingPosts Parameter an generateSocialPost uebergeben | Duplicate-Prevention |
