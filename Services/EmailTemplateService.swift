import Foundation

// MARK: - EmailTemplateService
// Verbesserung 8: Template-System mit mehreren Varianten
// Verwaltet Email-Templates pro Branche und Anlass
class EmailTemplateService {
    
    private var templates: [EmailTemplate] = []
    private let templatesURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        templatesURL = appDir.appendingPathComponent("emailTemplates.json")
        loadTemplates()
        if templates.isEmpty { seedDefaults() }
    }
    
    // MARK: - Template Selection
    func bestTemplate(for industry: String, type: TemplateType = .initial) -> EmailTemplate? {
        // Priority: industry-specific > general
        let matching = templates.filter { $0.type == type }
        return matching.first { $0.industry == industry }
            ?? matching.first { $0.industry == "general" }
    }
    
    func allTemplates(type: TemplateType? = nil) -> [EmailTemplate] {
        if let type = type { return templates.filter { $0.type == type } }
        return templates
    }
    
    // MARK: - Apply Template
    func applyTemplate(_ template: EmailTemplate, lead: Lead, senderName: String, challenges: String = "") -> (subject: String, body: String) {
        var subject = template.subjectTemplate
        var body = template.bodyTemplate
        
        let replacements: [String: String] = [
            "{{name}}": lead.name,
            "{{firstName}}": lead.name.components(separatedBy: " ").first ?? lead.name,
            "{{company}}": lead.company,
            "{{title}}": lead.title,
            "{{industry}}": template.industry,
            "{{sender}}": senderName,
            "{{challenges}}": challenges,
            "{{email}}": lead.email
        ]
        
        for (key, value) in replacements {
            subject = subject.replacingOccurrences(of: key, with: value)
            body = body.replacingOccurrences(of: key, with: value)
        }
        return (subject: subject, body: body)
    }
    
    // MARK: - CRUD
    func addTemplate(_ template: EmailTemplate) {
        templates.append(template)
        saveTemplates()
    }
    
    func updateTemplate(_ template: EmailTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
            saveTemplates()
        }
    }
    
    func deleteTemplate(_ id: UUID) {
        templates.removeAll { $0.id == id }
        saveTemplates()
    }
    
    // MARK: - Seed Defaults
    private func seedDefaults() {
        templates = [
            EmailTemplate(
                name: "Financial Services - Initial",
                industry: "K - Finanzdienstleistungen",
                type: .initial,
                subjectTemplate: "Regulatory compliance automation for {{company}}",
                bodyTemplate: "Dear {{firstName}},\n\nAs {{title}} at {{company}}, you are navigating an increasingly complex regulatory landscape including DORA, MiFID II, and AMLD6.\n\n{{challenges}}\n\nHarpocrates comply.reg automates regulatory change monitoring and impact assessment, reducing manual compliance effort by up to 60%.\n\nWould you be open to a brief conversation about how we support financial institutions like {{company}}?\n\nBest regards,\n{{sender}}\nHarpocrates Corp"
            ),
            EmailTemplate(
                name: "Healthcare - Initial",
                industry: "Q - Gesundheitswesen",
                type: .initial,
                subjectTemplate: "MDR/IVDR compliance simplified for {{company}}",
                bodyTemplate: "Dear {{firstName}},\n\nHealthcare organizations face mounting pressure from MDR, IVDR, and EU Health Data Space regulations.\n\n{{challenges}}\n\nHarpocrates comply.reg provides automated regulatory tracking specifically designed for healthcare compliance teams.\n\nCould we schedule 15 minutes to discuss how {{company}} could benefit?\n\nBest regards,\n{{sender}}\nHarpocrates Corp"
            ),
            EmailTemplate(
                name: "General Follow-Up",
                industry: "general",
                type: .followUp,
                subjectTemplate: "Re: {{company}} - following up",
                bodyTemplate: "Dear {{firstName}},\n\nI wanted to follow up on my previous message regarding compliance automation for {{company}}.\n\nI understand your schedule is demanding. If now is not the right time, I would be happy to reconnect when it suits you better.\n\nIn the meantime, you might find our regulatory update tracker useful. It monitors changes across all relevant frameworks for your industry.\n\nBest regards,\n{{sender}}\nHarpocrates Corp"
            )
        ]
        saveTemplates()
    }
    
    // MARK: - Persistence
    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            try? data.write(to: templatesURL, options: .atomic)
        }
    }
    
    private func loadTemplates() {
        guard let data = try? Data(contentsOf: templatesURL),
              let saved = try? JSONDecoder().decode([EmailTemplate].self, from: data) else { return }
        templates = saved
    }
}

// MARK: - Models
struct EmailTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var industry: String
    var type: TemplateType
    var subjectTemplate: String
    var bodyTemplate: String
    var createdDate: Date
    var usageCount: Int
    
    init(id: UUID = UUID(), name: String, industry: String,
         type: TemplateType = .initial, subjectTemplate: String,
         bodyTemplate: String, createdDate: Date = Date(), usageCount: Int = 0) {
        self.id = id
        self.name = name
        self.industry = industry
        self.type = type
        self.subjectTemplate = subjectTemplate
        self.bodyTemplate = bodyTemplate
        self.createdDate = createdDate
        self.usageCount = usageCount
    }
}

enum TemplateType: String, Codable, CaseIterable {
    case initial = "Initial Outreach"
    case followUp = "Follow-Up"
    case reEngagement = "Re-Engagement"
    case referral = "Referral Request"
}
