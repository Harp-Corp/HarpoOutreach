import Foundation

// MARK: - SubjectLineService
// Verbesserung 13: Subject-Line A/B Testing
// Generiert mehrere Subject-Varianten und trackt Performance
class SubjectLineService {
    
    private let pplxService = PerplexityService()
    
    // MARK: - Generate Subject Variants
    /// Generates 3 subject line variants for a given lead/company context
    func generateVariants(
        lead: Lead,
        challenges: String,
        apiKey: String
    ) async throws -> [SubjectVariant] {
        let prompt = """
        Generate exactly 3 different email subject lines for a cold outreach email.
        
        Target: \(lead.name), \(lead.title) at \(lead.company)
        Context: \(challenges.prefix(200))
        Sender: Harpocrates Corp (RegTech/Compliance solutions)
        
        Requirements:
        - Variant A: Direct value proposition (what they gain)
        - Variant B: Question-based (engaging curiosity)
        - Variant C: Industry-specific pain point
        - Each subject max 60 characters
        - No spam trigger words (free, urgent, act now)
        - Professional tone, no emojis
        
        Return ONLY a JSON array with 3 objects:
        [{"variant": "A", "subject": "...", "style": "value_prop"},
         {"variant": "B", "subject": "...", "style": "question"},
         {"variant": "C", "subject": "...", "style": "pain_point"}]
        """
        
        let response = try await pplxService.callAPI(
            systemPrompt: "You are an email subject line expert. Return only valid JSON.",
            userPrompt: prompt,
            apiKey: apiKey,
            maxTokens: 500
        )
        
        return parseVariants(response)
    }
    
    // MARK: - Track Performance
    func recordSend(variantID: UUID) {
        var stats = loadStats()
        if var entry = stats[variantID.uuidString] {
            entry.sends += 1
            stats[variantID.uuidString] = entry
        }
        saveStats(stats)
    }
    
    func recordOpen(variantID: UUID) {
        var stats = loadStats()
        if var entry = stats[variantID.uuidString] {
            entry.opens += 1
            stats[variantID.uuidString] = entry
        }
        saveStats(stats)
    }
    
    func recordReply(variantID: UUID) {
        var stats = loadStats()
        if var entry = stats[variantID.uuidString] {
            entry.replies += 1
            stats[variantID.uuidString] = entry
        }
        saveStats(stats)
    }
    
    // MARK: - Best Performing Style
    func bestPerformingStyle() -> String? {
        let stats = loadStats()
        let byStyle = Dictionary(grouping: stats.values, by: { $0.style })
        
        var bestStyle: String?
        var bestRate: Double = 0
        
        for (style, entries) in byStyle {
            let totalSends = entries.reduce(0) { $0 + $1.sends }
            let totalReplies = entries.reduce(0) { $0 + $1.replies }
            guard totalSends >= 5 else { continue } // Need minimum sample size
            let rate = Double(totalReplies) / Double(totalSends)
            if rate > bestRate {
                bestRate = rate
                bestStyle = style
            }
        }
        return bestStyle
    }
    
    // MARK: - Parse Variants from API Response
    private func parseVariants(_ response: String) -> [SubjectVariant] {
        let cleaned = pplxService.cleanJSON(response)
        guard let data = cleaned.data(using: .utf8) else { return defaultVariants() }
        
        do {
            let decoded = try JSONDecoder().decode([SubjectVariantJSON].self, from: data)
            return decoded.map { json in
                SubjectVariant(
                    variant: json.variant,
                    subject: json.subject,
                    style: json.style
                )
            }
        } catch {
            return defaultVariants()
        }
    }
    
    private func defaultVariants() -> [SubjectVariant] {
        return [
            SubjectVariant(variant: "A", subject: "Compliance automation for your industry", style: "value_prop"),
            SubjectVariant(variant: "B", subject: "How do you handle regulatory changes?", style: "question"),
            SubjectVariant(variant: "C", subject: "Regulatory risk: automated solutions exist", style: "pain_point")
        ]
    }
    
    // MARK: - Persistence
    private func statsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        return appDir.appendingPathComponent("subjectStats.json")
    }
    
    private func loadStats() -> [String: SubjectStats] {
        guard let data = try? Data(contentsOf: statsURL()),
              let stats = try? JSONDecoder().decode([String: SubjectStats].self, from: data)
        else { return [:] }
        return stats
    }
    
    private func saveStats(_ stats: [String: SubjectStats]) {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: statsURL(), options: .atomic)
        }
    }
}

// MARK: - Models
struct SubjectVariant: Identifiable, Codable {
    let id: UUID
    var variant: String  // "A", "B", "C"
    var subject: String
    var style: String    // "value_prop", "question", "pain_point"
    var isSelected: Bool
    
    init(id: UUID = UUID(), variant: String, subject: String,
         style: String, isSelected: Bool = false) {
        self.id = id
        self.variant = variant
        self.subject = subject
        self.style = style
        self.isSelected = isSelected
    }
}

struct SubjectStats: Codable {
    var style: String
    var sends: Int = 0
    var opens: Int = 0
    var replies: Int = 0
    
    var openRate: Double {
        guard sends > 0 else { return 0 }
        return Double(opens) / Double(sends) * 100
    }
    
    var replyRate: Double {
        guard sends > 0 else { return 0 }
        return Double(replies) / Double(sends) * 100
    }
}

private struct SubjectVariantJSON: Codable {
    let variant: String
    let subject: String
    let style: String
}
