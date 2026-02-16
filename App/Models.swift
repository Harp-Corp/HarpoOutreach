import Foundation

// MARK: - Industrien (harpocrates-corp.com)
enum Industry: String, CaseIterable, Identifiable, Codable {
    case healthcare = "Healthcare"
    case financialServices = "Financial Services"
    case energy = "Energy"
    case manufacturing = "Manufacturing"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .healthcare: return "cross.case.fill"
        case .financialServices: return "banknote.fill"
        case .energy: return "bolt.fill"
        case .manufacturing: return "gearshape.2.fill"
        }
    }
    
    var searchTerms: String {
        switch self {
        case .healthcare:
            return "healthcare, pharma, medical devices, biotech, hospitals"
        case .financialServices:
            return "banking, insurance, asset management, fintech"
        case .energy:
            return "energy, utilities, oil gas, renewables, solar wind"
        case .manufacturing:
            return "manufacturing, industrial, automotive, chemicals"
        }
    }
}

// MARK: - Regionen
enum Region: String, CaseIterable, Identifiable, Codable {
    case dach = "DACH"
    case uk = "UK"
    case baltics = "Baltics"
    case nordics = "Nordics"
    
    var id: String { rawValue }
    
    var countries: String {
        switch self {
        case .dach: return "Germany, Austria, Switzerland"
        case .uk: return "United Kingdom"
        case .baltics: return "Estonia, Latvia, Lithuania"
        case .nordics: return "Sweden, Norway, Denmark, Finland"
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
    
    init(id: UUID = UUID(), name: String, industry: String, region: String,
         website: String = "", linkedInURL: String = "", description: String = "",
         size: String = "", country: String = "") {
        self.id = id
        self.name = name
        self.industry = industry
        self.region = region
        self.website = website
        self.linkedInURL = linkedInURL
        self.description = description
        self.size = size
        self.country = country
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
    var isManuallyCreated: Bool  // NEU: Flag für manuelle Erstellung
    
    init(id: UUID = UUID(), name: String, title: String, company: String,
         email: String, emailVerified: Bool = false, linkedInURL: String = "",
         phone: String = "", responsibility: String = "", status: LeadStatus = .identified,
         source: String = "", verificationNotes: String = "",
         draftedEmail: OutboundEmail? = nil, followUpEmail: OutboundEmail? = nil,
         dateIdentified: Date = Date(), dateEmailSent: Date? = nil,
         dateFollowUpSent: Date? = nil, replyReceived: String = "",
         isManuallyCreated: Bool = false) {
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

// MARK: - Email Draft (NEU für Draft-Management)
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
    var isFollowUp: Bool  // true = follow-up, false = initial email
    
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
    
    init() {
        perplexityAPIKey = ""
        googleClientID = ""
        googleClientSecret = ""
        spreadsheetID = ""
        senderEmail = "mf@harpocrates-corp.com"
        senderName = "Martin Förster"
        selectedIndustries = Industry.allCases.map { $0.rawValue }
        selectedRegions = Region.allCases.map { $0.rawValue }
    }
}
