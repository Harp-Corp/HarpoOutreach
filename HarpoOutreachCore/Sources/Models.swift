// HarpoOutreachCore - Shared Models
// Platform-independent data models for macOS App + Web Server

import Foundation

// MARK: - Industry (NACE Rev. 2)
public enum Industry: String, CaseIterable, Identifiable, Codable, Sendable {
    case Q_healthcare = "Q - Gesundheitswesen"
    case K_financialServices = "K - Finanzdienstleistungen"
    case D_energy = "D - Energieversorgung"
    case C_manufacturing = "C - Verarbeitendes Gewerbe"
    case J_infoComm = "J - Information und Kommunikation"
    case H_transport = "H - Verkehr und Lagerei"
    case M_professional = "M - Freiberufliche Dienstleistungen"

    public var id: String { rawValue }

    public var shortName: String {
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

    public var naceSection: String {
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

    public var keyRegulations: String {
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

    public var searchTerms: String {
        switch self {
        case .Q_healthcare: return "healthcare, pharma, medical devices, biotech"
        case .K_financialServices: return "banking, insurance, asset management, fintech"
        case .D_energy: return "energy, utilities, renewables, solar, wind"
        case .C_manufacturing: return "manufacturing, industrial, automotive, chemicals"
        case .J_infoComm: return "software, IT services, telecommunications, cloud"
        case .H_transport: return "logistics, transport, shipping, freight, warehousing"
        case .M_professional: return "consulting, legal, accounting, engineering"
        }
    }
}

// MARK: - Region
public enum Region: String, CaseIterable, Identifiable, Codable, Sendable {
    case dach = "DACH"
    case uk = "UK"
    case baltics = "Baltics"
    case nordics = "Nordics"
    case benelux = "Benelux"
    case france = "France"
    case iberia = "Iberia"

    public var id: String { rawValue }

    public var countries: String {
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

// MARK: - CompanySize
public enum CompanySize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small = "0-200 Mitarbeiter"
    case medium = "201-5.000 Mitarbeiter"
    case large = "5.001-500.000 Mitarbeiter"

    public var id: String { rawValue }
    public var shortName: String {
        switch self {
        case .small: return "Klein (0-200)"
        case .medium: return "Mittel (201-5K)"
        case .large: return "Gross (5K-500K)"
        }
    }
}

// MARK: - Lead Status
public enum LeadStatus: String, Codable, CaseIterable, Sendable {
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

// MARK: - Company (API-transportable)
public struct CompanyDTO: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var industry: String
    public var region: String
    public var website: String
    public var linkedInURL: String
    public var description: String
    public var size: String
    public var country: String
    public var naceCode: String
    public var employeeCount: Int

    public init(id: UUID = UUID(), name: String, industry: String, region: String,
                website: String = "", linkedInURL: String = "", description: String = "",
                size: String = "", country: String = "", naceCode: String = "", employeeCount: Int = 0) {
        self.id = id; self.name = name; self.industry = industry; self.region = region
        self.website = website; self.linkedInURL = linkedInURL; self.description = description
        self.size = size; self.country = country; self.naceCode = naceCode; self.employeeCount = employeeCount
    }
}

// MARK: - Lead (API-transportable)
public struct LeadDTO: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var title: String
    public var company: String
    public var email: String
    public var emailVerified: Bool
    public var linkedInURL: String
    public var status: LeadStatus
    public var source: String
    public var dateIdentified: Date

    public init(id: UUID = UUID(), name: String, title: String = "", company: String,
                email: String, emailVerified: Bool = false, linkedInURL: String = "",
                status: LeadStatus = .identified, source: String = "", dateIdentified: Date = Date()) {
        self.id = id; self.name = name; self.title = title; self.company = company
        self.email = email; self.emailVerified = emailVerified; self.linkedInURL = linkedInURL
        self.status = status; self.source = source; self.dateIdentified = dateIdentified
    }
}

// MARK: - Email Draft (API-transportable)
public struct EmailDraftDTO: Codable, Identifiable, Sendable {
    public var id: UUID
    public var leadId: UUID
    public var leadName: String
    public var leadEmail: String
    public var companyName: String
    public var subject: String
    public var body: String
    public var isFollowUp: Bool

    public init(id: UUID = UUID(), leadId: UUID, leadName: String, leadEmail: String,
                companyName: String, subject: String, body: String, isFollowUp: Bool = false) {
        self.id = id; self.leadId = leadId; self.leadName = leadName; self.leadEmail = leadEmail
        self.companyName = companyName; self.subject = subject; self.body = body; self.isFollowUp = isFollowUp
    }
}

// MARK: - Social Post (API-transportable)
public enum SocialPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case linkedin = "LinkedIn"
    case twitter = "Twitter/X"
    public var id: String { rawValue }
}

public enum ContentTopic: String, CaseIterable, Identifiable, Codable, Sendable {
    case regulatoryUpdate = "Regulatory Update"
    case complianceTip = "Compliance Tip"
    case industryInsight = "Industry Insight"
    case productFeature = "Product Feature"
    case thoughtLeadership = "Thought Leadership"
    case caseStudy = "Case Study"
    public var id: String { rawValue }
}

public struct SocialPostDTO: Codable, Identifiable, Sendable {
    public var id: UUID
    public var platform: SocialPlatform
    public var content: String
    public var hashtags: [String]
    public var createdDate: Date
    public var isPublished: Bool

    public init(id: UUID = UUID(), platform: SocialPlatform, content: String,
                hashtags: [String] = [], createdDate: Date = Date(), isPublished: Bool = false) {
        self.id = id; self.platform = platform; self.content = content
        self.hashtags = hashtags; self.createdDate = createdDate; self.isPublished = isPublished
    }
}

// MARK: - Dashboard Stats
public struct DashboardStats: Codable, Sendable {
    public var totalLeads: Int
    public var emailsSent: Int
    public var repliesReceived: Int
    public var conversionRate: Double
    public var leadsByStatus: [String: Int]
    public var leadsByIndustry: [String: Int]

    public init(totalLeads: Int = 0, emailsSent: Int = 0, repliesReceived: Int = 0,
                conversionRate: Double = 0, leadsByStatus: [String: Int] = [:],
                leadsByIndustry: [String: Int] = [:]) {
        self.totalLeads = totalLeads; self.emailsSent = emailsSent
        self.repliesReceived = repliesReceived; self.conversionRate = conversionRate
        self.leadsByStatus = leadsByStatus; self.leadsByIndustry = leadsByIndustry
    }
}

// MARK: - API Request/Response
public struct SearchCompaniesRequest: Codable, Sendable {
    public var industry: String
    public var region: String
    public init(industry: String, region: String) {
        self.industry = industry; self.region = region
    }
}

public struct DraftEmailRequest: Codable, Sendable {
    public var leadId: UUID
    public var isFollowUp: Bool
    public init(leadId: UUID, isFollowUp: Bool = false) {
        self.leadId = leadId; self.isFollowUp = isFollowUp
    }
}

public struct SendEmailRequest: Codable, Sendable {
    public var leadId: UUID
    public var subject: String
    public var body: String
    public init(leadId: UUID, subject: String, body: String) {
        self.leadId = leadId; self.subject = subject; self.body = body
    }
}

public struct GeneratePostRequest: Codable, Sendable {
    public var topic: ContentTopic
    public var platform: SocialPlatform
    public var industries: [String]
    public init(topic: ContentTopic, platform: SocialPlatform, industries: [String] = []) {
        self.topic = topic; self.platform = platform; self.industries = industries
    }
}

public struct APIResponse<T: Codable>: Codable where T: Sendable {
    public var success: Bool
    public var data: T?
    public var error: String?
    public init(success: Bool, data: T? = nil, error: String? = nil) {
        self.success = success; self.data = data; self.error = error
    }
}
