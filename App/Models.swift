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
        case .C_manufacturing: return "manufacturing, industrial, automotive, chemicals, Maschinenbau, Fertigung"
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
    var naceCode: String  // z.B. "K64.1" oder "C26.5"

    init(id: UUID = UUID(), name: String, industry: String, region: String,
         website: String = "", linkedInURL: String = "", description: String = "",
         size: String = "", country: String = "", naceCode: String = "") {
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
    var unsubscribed: Bool
    var unsubscribedDate: Date?

    init(id: UUID = UUID(), name: String, title: String = "", company: String,
         email: String, emailVerified: Bool = false, linkedInURL: String = "",
         phone: String = "", responsibility: String = "",
         status: LeadStatus = .identified, source: String = "",
         verificationNotes: String = "", draftedEmail: OutboundEmail? = nil,
         followUpEmail: OutboundEmail? = nil, dateIdentified: Date = Date(),
         dateEmailSent: Date? = nil, dateFollowUpSent: Date? = nil,
         replyReceived: String = "", isManuallyCreated: Bool = false,
         unsubscribed: Bool = false, unsubscribedDate: Date? = nil) {
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
        self.unsubscribed = unsubscribed
        self.unsubscribedDate = unsubscribedDate
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
    var spreadsheetID: String
    var senderEmail: String
    var senderName: String
    var selectedIndustries: [String]
    var selectedRegions: [String]
    var linkedInAccessToken: String
    var linkedInClientID: String
    var linkedInClientSecret: String
    var linkedInOrgId: String

    init() {
        perplexityAPIKey = ""
        googleClientID = ""
        googleClientSecret = ""
        spreadsheetID = ""
        senderEmail = "mf@harpocrates-corp.com"
        senderName = "Martin Foerster"
        selectedIndustries = Industry.allCases.map { $0.rawValue }
        selectedRegions = Region.allCases.map { $0.rawValue }
        linkedInAccessToken = ""
        linkedInClientID = "77ttejuk0kfo3j"
        linkedInClientSecret = "WPL_AP1.xSnY6qv2ICR5zI78.FUl1AQ=="
        linkedInOrgId = "42109305"
    }
}

// MARK: - Social Post Platform
enum SocialPlatform: String, Codable, CaseIterable {
    case linkedIn = "LinkedIn"
    case twitter = "Twitter"
}

// MARK: - Social Post Status
enum SocialPostStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case approved = "Approved"
    case published = "Published"
    case failed = "Failed"
}

// MARK: - Social Post
struct SocialPost: Identifiable, Codable, Hashable {
    let id: UUID
    var platform: SocialPlatform
    var content: String
    var hashtags: [String]
    var status: SocialPostStatus
    var createdDate: Date
    var publishedDate: Date?
    var postURL: String
    var engagementLikes: Int
    var engagementComments: Int
    var engagementShares: Int
    var campaignId: UUID?

    init(id: UUID = UUID(), platform: SocialPlatform = .linkedIn,
         content: String, hashtags: [String] = [],
         status: SocialPostStatus = .draft, createdDate: Date = Date(),
         publishedDate: Date? = nil, postURL: String = "",
         engagementLikes: Int = 0, engagementComments: Int = 0,
         engagementShares: Int = 0, campaignId: UUID? = nil) {
        self.id = id
        self.platform = platform
        self.content = content
        self.hashtags = hashtags
        self.status = status
        self.createdDate = createdDate
        self.publishedDate = publishedDate
        self.postURL = postURL
        self.engagementLikes = engagementLikes
        self.engagementComments = engagementComments
        self.engagementShares = engagementShares
        self.campaignId = campaignId
    }
}

// MARK: - Newsletter Campaign Status
enum CampaignStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case scheduled = "Scheduled"
    case sending = "Sending"
    case sent = "Sent"
    case failed = "Failed"
}

// MARK: - Newsletter Campaign
struct NewsletterCampaign: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var subject: String
    var htmlBody: String
    var plainTextBody: String
    var targetIndustries: [String]
    var targetRegions: [String]
    var recipientCount: Int
    var sentCount: Int
    var openCount: Int
    var clickCount: Int
    var unsubscribeCount: Int
    var bounceCount: Int
    var status: CampaignStatus
    var createdDate: Date
    var scheduledDate: Date?
    var sentDate: Date?
    var socialPosts: [SocialPost]

    init(id: UUID = UUID(), name: String, subject: String,
         htmlBody: String = "", plainTextBody: String = "",
         targetIndustries: [String] = [], targetRegions: [String] = [],
         recipientCount: Int = 0, sentCount: Int = 0,
         openCount: Int = 0, clickCount: Int = 0,
         unsubscribeCount: Int = 0, bounceCount: Int = 0,
         status: CampaignStatus = .draft, createdDate: Date = Date(),
         scheduledDate: Date? = nil, sentDate: Date? = nil,
         socialPosts: [SocialPost] = []) {
        self.id = id
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainTextBody = plainTextBody
        self.targetIndustries = targetIndustries
        self.targetRegions = targetRegions
        self.recipientCount = recipientCount
        self.sentCount = sentCount
        self.openCount = openCount
        self.clickCount = clickCount
        self.unsubscribeCount = unsubscribeCount
        self.bounceCount = bounceCount
        self.status = status
        self.createdDate = createdDate
        self.scheduledDate = scheduledDate
        self.sentDate = sentDate
        self.socialPosts = socialPosts
    }
}

// MARK: - Content Topic (fuer KI-generierte Inhalte)
enum ContentTopic: String, Codable, CaseIterable, Identifiable {
    case regulatoryUpdate = "Regulatory Update"
    case complianceBestPractices = "Compliance Best Practices"
    case industryTrends = "Industry Trends"
    case productUpdate = "Product Update"
    case caseStudy = "Case Study"
    case thoughtLeadership = "Thought Leadership"
    case eventAnnouncement = "Event Announcement"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .regulatoryUpdate: return "Neueste regulatorische Aenderungen und deren Auswirkungen"
        case .complianceBestPractices: return "Bewaehrte Methoden fuer Compliance-Management"
        case .industryTrends: return "Aktuelle Branchentrends und Marktentwicklungen"
        case .productUpdate: return "Neuigkeiten zu Harpocrates Produkten und Features"
        case .caseStudy: return "Erfolgsgeschichten und Anwendungsbeispiele"
        case .thoughtLeadership: return "Expertenmeinungen und strategische Einblicke"
        case .eventAnnouncement: return "Veranstaltungen, Webinare und Konferenzen"
        }
    }

    var promptPrefix: String {
        switch self {
        case .regulatoryUpdate: return "Write about recent regulatory changes in"
        case .complianceBestPractices: return "Share compliance best practices for"
        case .industryTrends: return "Analyze current industry trends in"
        case .productUpdate: return "Announce product updates for compliance automation in"
        case .caseStudy: return "Present a case study about compliance automation in"
        case .thoughtLeadership: return "Provide expert insights on compliance challenges in"
        case .eventAnnouncement: return "Announce an upcoming compliance event for"
        }
    }
}
