import Foundation

// MARK: - Industrien nach NACE Rev. 2 (EU-Branchenklassifikation)
// Nomenclature statistique des activites economiques dans la Communaute europeenne
enum Industry: String, CaseIterable, Identifiable, Codable {
    // Sektion Q - Gesundheits- und Sozialwesen
    case Q_healthcare = "Q - Gesundheitswesen"

    // Sektion K - Finanz- und Versicherungsdienstleistungen
    case K_financialServices = "K - Finanzdienstleistungen"

    // Sektion D - Energieversorgung
    case D_energy = "D - Energieversorgung"

    // Sektion C - Verarbeitendes Gewerbe
    case C_manufacturing = "C - Verarbeitendes Gewerbe"

    // Sektion J - Information und Kommunikation
    case J_infoComm = "J - Information und Kommunikation"

    // Sektion H - Verkehr und Lagerei
    case H_transport = "H - Verkehr und Lagerei"

    // Sektion M - Freiberufliche, wissenschaftliche und technische Dienstleistungen
    case M_professional = "M - Freiberufliche Dienstleistungen"

    var id: String { rawValue }

    /// NACE Sektionsbuchstabe
    var naceSection: String {
        switch self {
        case .Q_healthcare: return "Q"
        case .K_financialServices: return "K"
        case .D_energy: return "D"
        case .C_manufacturing: return "C"
        case .J_infoComm: return "J"
        case .H_transport: return "H"
        case .M_professional: return "M"
        }
    }

    /// SF6-Symbol fuer die UI
    var icon: String {
        switch self {
        case .Q_healthcare: return "cross.case.fill"
        case .K_financialServices: return "banknote.fill"
        case .D_energy: return "bolt.fill"
        case .C_manufacturing: return "gearshape.2.fill"
        case .J_infoComm: return "network"
        case .H_transport: return "shippingbox.fill"
        case .M_professional: return "briefcase.fill"
        }
    }

    /// Kurzname fuer Anzeige in Listen
    var shortName: String {
        switch self {
        case .Q_healthcare: return "Healthcare"
        case .K_financialServices: return "Financial Services"
        case .D_energy: return "Energy"
        case .C_manufacturing: return "Manufacturing"
        case .J_infoComm: return "ICT"
        case .H_transport: return "Transport & Logistics"
        case .M_professional: return "Professional Services"
        }
    }

    /// NACE-Divisionen (2-Steller) die unter diese Sektion fallen
    var naceDivisions: String {
        switch self {
        case .Q_healthcare: return "86-88"
        case .K_financialServices: return "64-66"
        case .D_energy: return "35"
        case .C_manufacturing: return "10-33"
        case .J_infoComm: return "58-63"
        case .H_transport: return "49-53"
        case .M_professional: return "69-75"
        }
    }

    /// Suchbegriffe fuer die Perplexity-Unternehmenssuche
    var searchTerms: String {
        switch self {
        case .Q_healthcare: return "healthcare, pharma, medical devices, biotech, hospitals, Gesundheitswesen, Medizintechnik"
        case .K_financialServices: return "banking, insurance, asset management, fintech, Finanzdienstleistungen, Versicherungen"
        case .D_energy: return "energy, utilities, renewables, solar, wind, Energieversorgung, Stadtwerke"
        case .C_manufacturing: return "manufacturing, industrial, automotive, automotive suppliers, Automobilzulieferer, OEM, Tier 1, Tier 2, chemicals, Maschinenbau, Fertigung, Fahrzeugbau, Automobilindustrie"
        case .J_infoComm: return "software, IT services, telecommunications, data processing, cloud computing"
        case .H_transport: return "logistics, transport, shipping, freight, warehousing, supply chain"
        case .M_professional: return "consulting, legal, accounting, engineering, R&D, Beratung, Wirtschaftspruefung"
        }
    }

    /// Relevante EU-Regulierungen fuer diese Branche
    var keyRegulations: String {
        switch self {
        case .Q_healthcare: return "MDR, IVDR, GDPR/DSGVO, EU Health Data Space, NIS2"
        case .K_financialServices: return "MiFID II, DORA, PSD2, AMLD6, Basel III/IV, DSGVO, ESG-Reporting"
        case .D_energy: return "EU ETS, RED III, REMIT, NIS2, ESG, Energieeffizienzrichtlinie"
        case .C_manufacturing: return "Maschinenverordnung, REACH, RoHS, CSRD, Lieferkettengesetz, ISO 27001"
        case .J_infoComm: return "EU AI Act, NIS2, DSGVO, Digital Services Act, Data Act, Cyber Resilience Act"
        case .H_transport: return "EU Mobility Package, NIS2, DSGVO, ADR/RID, EU ETS Seeverkehr"
        case .M_professional: return "DSGVO, Geldwaeschegesetz, EU AI Act, Berufsrecht, CSRD"
        }
    }
}

// MARK: - Regionen
enum Region: String, CaseIterable, Identifiable, Codable {
    case dach = "DACH"
    case uk = "UK"
    case baltics = "Baltics"
    case nordics = "Nordics"
    case benelux = "Benelux"
    case france = "France"
    case iberia = "Iberia"

    var id: String { rawValue }

    var countries: String {
        switch self {
        case .dach: return "Germany, Austria, Switzerland"
        case .uk: return "United Kingdom"
        case .baltics: return "Estonia, Latvia, Lithuania"
        case .nordics: return "Sweden, Norway, Denmark, Finland"
        case .benelux: return "Belgium, Netherlands, Luxembourg"
        case .france: return "France"
        case .iberia: return "Spain, Portugal"
        }
    }
}

// MARK: - Unternehmensgroesse
enum CompanySize: String, CaseIterable, Identifiable, Codable {
    case small = "0-200 Mitarbeiter"
    case medium = "201-5.000 Mitarbeiter"
    case large = "5.001-500.000 Mitarbeiter"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .small: return "Klein (0-200)"
        case .medium: return "Mittel (201-5K)"
        case .large: return "Gross (5K-500K)"
        }
    }

    var icon: String {
        switch self {
        case .small: return "building.2"
        case .medium: return "building.2.fill"
        case .large: return "building.columns.fill"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .small: return 0...200
        case .medium: return 201...5000
        case .large: return 5001...500000
        }
    }

    /// Prueft ob eine Mitarbeiterzahl in diesen Groessenbereich faellt
    func matches(employeeCount: Int) -> Bool {
        return range.contains(employeeCount)
    }
}

// MARK: - Unternehmen
struct Company: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var industry: String
    var region: String
    var website: String
    var linkedInURL: String
    var description: String
    var size: String
    var country: String
    var naceCode: String // z.B. "K64.1" oder "C26.5"
    var employeeCount: Int

    init(id: UUID = UUID(), name: String, industry: String, region: String,
         website: String = "", linkedInURL: String = "", description: String = "",
         size: String = "", country: String = "", naceCode: String = "",
         employeeCount: Int = 0) {
        self.id = id
        self.name = name
        self.industry = industry
        self.region = region
        self.website = website
        self.linkedInURL = linkedInURL
        self.description = description
        self.size = size
        self.country = country
        self.naceCode = naceCode
        self.employeeCount = employeeCount
    }
}

// MARK: - Lead Status
enum LeadStatus: String, Codable, CaseIterable {
    case identified = "Identified"
    case contacted = "Contacted"
    case followedUp = "Followed Up"
    case qualified = "Qualified"
    case converted = "Converted"
    case notInterested = "Not Interested"
    case emailApproved = "Email Approved"
    case emailDrafted = "Email Drafted"
    case emailSent = "Email Sent"
    case followUpDrafted = "Follow-Up Drafted"
    case followUpSent = "Follow-Up Sent"
    case replied = "Replied"
    case doNotContact = "Do Not Contact"
    case closed = "Closed"
}

// MARK: - Lead
struct Lead: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var title: String
    var company: String
    var email: String
    var emailVerified: Bool
    var linkedInURL: String
    var phone: String
    var responsibility: String
    var status: LeadStatus
    var source: String
    var verificationNotes: String
    var draftedEmail: OutboundEmail?
    var followUpEmail: OutboundEmail?
    var dateIdentified: Date
    var dateEmailSent: Date?
    var dateFollowUpSent: Date?
    var replyReceived: String
    var isManuallyCreated: Bool

    init(id: UUID = UUID(), name: String, title: String = "", company: String,
         email: String, emailVerified: Bool = false, linkedInURL: String = "",
         phone: String = "", responsibility: String = "",
         status: LeadStatus = .identified, source: String = "",
         verificationNotes: String = "", draftedEmail: OutboundEmail? = nil,
         followUpEmail: OutboundEmail? = nil, dateIdentified: Date = Date(),
         dateEmailSent: Date? = nil, dateFollowUpSent: Date? = nil,
         replyReceived: String = "", isManuallyCreated: Bool = false) {
        self.id = id
        self.name = name
        self.title = title
        self.company = company
        self.email = email
        self.emailVerified = emailVerified
        self.linkedInURL = linkedInURL
        self.phone = phone
        self.responsibility = responsibility
        self.status = status
        self.source = source
        self.verificationNotes = verificationNotes
        self.draftedEmail = draftedEmail
        self.followUpEmail = followUpEmail
        self.dateIdentified = dateIdentified
        self.dateEmailSent = dateEmailSent
        self.dateFollowUpSent = dateFollowUpSent
        self.replyReceived = replyReceived
        self.isManuallyCreated = isManuallyCreated
    }
}

// MARK: - Outbound Email
struct OutboundEmail: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: String
    var body: String
    var isApproved: Bool
    var sentDate: Date?

    init(id: UUID = UUID(), subject: String, body: String,
         isApproved: Bool = false, sentDate: Date? = nil) {
        self.id = id
        self.subject = subject
        self.body = body
        self.isApproved = isApproved
        self.sentDate = sentDate
    }
}

// MARK: - Email Draft (fuer Draft-Management)
struct EmailDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var leadId: UUID
    var leadName: String
    var leadEmail: String
    var companyName: String
    var subject: String
    var body: String
    var createdDate: Date
    var lastModifiedDate: Date
    var isFollowUp: Bool

    init(id: UUID = UUID(), leadId: UUID, leadName: String, leadEmail: String,
         companyName: String, subject: String, body: String,
         createdDate: Date = Date(), lastModifiedDate: Date = Date(),
         isFollowUp: Bool = false) {
        self.id = id
        self.leadId = leadId
        self.leadName = leadName
        self.leadEmail = leadEmail
        self.companyName = companyName
        self.subject = subject
        self.body = body
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.isFollowUp = isFollowUp
    }
}

// MARK: - App Settings
struct AppSettings: Codable {
    var perplexityAPIKey: String
    var googleClientID: String
    var googleClientSecret: String
    var linkedInClientID: String
    var linkedInClientSecret: String
    var spreadsheetID: String
    var senderEmail: String
    var senderName: String
    var selectedIndustries: [String]
    var selectedRegions: [String]
    var selectedCompanySizes: [String]

    init() {
        perplexityAPIKey = "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"
        googleClientID = "321117608826-6ta6m1vdrf3sm7qf8ckf89r7uc0vc7m5.apps.googleusercontent.com"
        googleClientSecret = ""
        linkedInClientID = "77ttejuk0kfo3j"
        linkedInClientSecret = "WPL_AP1.xSnY6qv2ICR5zI78.FUl1AQ=="
        spreadsheetID = ""
        senderEmail = "mf@harpocrates-corp.com"
        senderName = "Martin Foerster"
        selectedIndustries = Industry.allCases.map { $0.rawValue }
        selectedRegions = Region.allCases.map { $0.rawValue }
        selectedCompanySizes = CompanySize.allCases.map { $0.rawValue }
    }
}

// MARK: - Social Media Content
enum SocialPlatform: String, CaseIterable, Identifiable, Codable {
    case linkedin = "LinkedIn"
    case twitter = "Twitter/X"

    var id: String { rawValue }
}

enum ContentTopic: String, CaseIterable, Identifiable, Codable {
    case regulatoryUpdate = "Regulatory Update"
    case complianceTip = "Compliance Tip"
    case industryInsight = "Industry Insight"
    case productFeature = "Product Feature"
    case thoughtLeadership = "Thought Leadership"
    case caseStudy = "Case Study"

    var id: String { rawValue }

    var promptPrefix: String {
        switch self {
        case .regulatoryUpdate: return "Aktuelle regulatorische Entwicklung in"
        case .complianceTip: return "Praxistipp fuer Compliance-Teams in"
        case .industryInsight: return "Brancheneinblick und Trends in"
        case .productFeature: return "Harpocrates comply.reg Feature fuer"
        case .thoughtLeadership: return "Expertenmeinung zu Compliance in"
        case .caseStudy: return "Praxisbeispiel Compliance-Herausforderung in"
        }
    }
}

struct SocialPost: Identifiable, Codable, Hashable {
    let id: UUID
    var platform: SocialPlatform
    var content: String {
        didSet {
            // BULLETPROOF: Footer wird bei JEDER Aenderung von content erzwungen
            if !content.hasSuffix("info@harpocrates-corp.com") {
                content = SocialPost.ensureFooter(content)
            }
        }
    }
    var hashtags: [String]
    var createdDate: Date
    var isPublished: Bool

    // PFLICHT-Footer fuer ALLE Social Posts
    static let companyFooter = "\n\n\u{1F517} www.harpocrates-corp.com | \u{1F4E7} info@harpocrates-corp.com"

    // Stellt sicher, dass der Footer IMMER am Ende des Contents steht
    static func ensureFooter(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Entferne existierenden Footer falls vorhanden
        if let range = clean.range(of: "\u{1F517} www.harpocrates-corp.com") {
            clean = String(clean[clean.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = clean.range(of: "harpocrates-corp.com | ") {
            clean = String(clean[clean.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean + companyFooter
    }

    init(id: UUID = UUID(), platform: SocialPlatform = .linkedin, content: String,
         hashtags: [String] = [], createdDate: Date = Date(), isPublished: Bool = false) {
        self.id = id
        self.platform = platform
        // FOOTER ENFORCEMENT: Immer Footer anhaengen
        self.content = SocialPost.ensureFooter(content)
        self.hashtags = hashtags
        self.createdDate = createdDate
        self.isPublished = isPublished
    }

    // Custom Codable: Footer auch beim Laden von Disk erzwingen
    enum CodingKeys: String, CodingKey {
        case id, platform, content, hashtags, createdDate, isPublished
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.platform = try container.decode(SocialPlatform.self, forKey: .platform)
        let rawContent = try container.decode(String.self, forKey: .content)
        // FOOTER ENFORCEMENT: Auch beim Laden von JSON/Disk
        self.content = SocialPost.ensureFooter(rawContent)
        self.hashtags = try container.decode([String].self, forKey: .hashtags)
        self.createdDate = try container.decode(Date.self, forKey: .createdDate)
        self.isPublished = try container.decode(Bool.self, forKey: .isPublished)
    }
}

// MARK: - Company Search Filters
extension Array where Element == Company {
    /// Filtert Unternehmen heraus, die bereits gespeicherte Leads haben
    func excludingExistingLeads(_ leads: [Lead]) -> [Company] {
        let existingCompanyNames = Set(leads.map { $0.company.lowercased().trimmingCharacters(in: .whitespaces) })
        return self.filter { company in
            !existingCompanyNames.contains(company.name.lowercased().trimmingCharacters(in: .whitespaces))
        }
    }

    /// Filtert Unternehmen nach ausgewaehlten Groessenkategorien
    func filterBySize(selectedSizes: [CompanySize]) -> [Company] {
        guard !selectedSizes.isEmpty else { return self }
        return self.filter { company in
            selectedSizes.contains { size in
                size.matches(employeeCount: company.employeeCount)
            }
        }
    }

    /// Kombinierter Filter: Groesse + bestehende Leads ausschliessen
    func applySearchFilters(selectedSizes: [CompanySize], existingLeads: [Lead]) -> [Company] {
        return self
            .filterBySize(selectedSizes: selectedSizes)
            .excludingExistingLeads(existingLeads)
    }
}
