import Foundation

// MARK: - AnalyticsService
// Verbesserung 7: Erweiterte Analytics und Metriken
// Trackt alle Outreach-Events und berechnet KPIs
@MainActor
class AnalyticsService: ObservableObject {
    
    @Published var events: [AnalyticsEvent] = []
    private let eventsURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HarpoOutreach", isDirectory: true)
        eventsURL = appDir.appendingPathComponent("analytics.json")
        loadEvents()
    }
    
    // MARK: - Track Events
    func track(_ type: EventType, leadID: UUID? = nil, metadata: [String: String] = [:]) {
        let event = AnalyticsEvent(type: type, leadID: leadID, metadata: metadata)
        events.append(event)
        saveEvents()
    }
    
    // MARK: - KPIs
    var emailOpenRate: Double {
        let sent = events.filter { $0.type == .emailSent }.count
        let opened = events.filter { $0.type == .emailOpened }.count
        guard sent > 0 else { return 0 }
        return Double(opened) / Double(sent) * 100
    }
    
    var replyRate: Double {
        let sent = events.filter { $0.type == .emailSent }.count
        let replied = events.filter { $0.type == .replyReceived }.count
        guard sent > 0 else { return 0 }
        return Double(replied) / Double(sent) * 100
    }
    
    var averageTimeToReply: TimeInterval {
        let sentEvents = events.filter { $0.type == .emailSent }
        let replyEvents = events.filter { $0.type == .replyReceived }
        var totalTime: TimeInterval = 0
        var matchCount = 0
        
        for reply in replyEvents {
            guard let leadID = reply.leadID,
                  let sent = sentEvents.first(where: { $0.leadID == leadID }) else { continue }
            totalTime += reply.timestamp.timeIntervalSince(sent.timestamp)
            matchCount += 1
        }
        return matchCount > 0 ? totalTime / Double(matchCount) : 0
    }
    
    var conversionFunnel: ConversionFunnel {
        ConversionFunnel(
            companiesFound: events.filter { $0.type == .companyFound }.count,
            contactsFound: events.filter { $0.type == .contactFound }.count,
            emailsVerified: events.filter { $0.type == .emailVerified }.count,
            emailsDrafted: events.filter { $0.type == .emailDrafted }.count,
            emailsSent: events.filter { $0.type == .emailSent }.count,
            repliesReceived: events.filter { $0.type == .replyReceived }.count,
            followUpsSent: events.filter { $0.type == .followUpSent }.count
        )
    }
    
    // MARK: - Time-based analytics
    func eventsInPeriod(days: Int) -> [AnalyticsEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return events.filter { $0.timestamp >= cutoff }
    }
    
    func dailyCounts(days: Int = 30) -> [(date: String, sent: Int, replies: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var result: [(date: String, sent: Int, replies: Int)] = []
        
        for i in (0..<days).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = formatter.string(from: date)
            let dayEvents = events.filter { formatter.string(from: $0.timestamp) == dateStr }
            result.append((
                date: dateStr,
                sent: dayEvents.filter { $0.type == .emailSent }.count,
                replies: dayEvents.filter { $0.type == .replyReceived }.count
            ))
        }
        return result
    }
    
    // MARK: - Industry performance
    func performanceByIndustry() -> [IndustryPerformance] {
        let byIndustry = Dictionary(grouping: events.filter { $0.metadata["industry"] != nil }) {
            $0.metadata["industry"]!
        }
        return byIndustry.map { industry, events in
            IndustryPerformance(
                industry: industry,
                sent: events.filter { $0.type == .emailSent }.count,
                replies: events.filter { $0.type == .replyReceived }.count,
                conversions: events.filter { $0.type == .leadConverted }.count
            )
        }.sorted { $0.replyRate > $1.replyRate }
    }
    
    // MARK: - Persistence
    private func saveEvents() {
        // Keep only last 10000 events
        if events.count > 10000 { events = Array(events.suffix(10000)) }
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: eventsURL, options: .atomic)
        }
    }
    
    private func loadEvents() {
        guard let data = try? Data(contentsOf: eventsURL),
              let saved = try? JSONDecoder().decode([AnalyticsEvent].self, from: data) else { return }
        events = saved
    }
}

// MARK: - Models
struct AnalyticsEvent: Identifiable, Codable {
    let id: UUID
    let type: EventType
    let leadID: UUID?
    let timestamp: Date
    let metadata: [String: String]
    
    init(id: UUID = UUID(), type: EventType, leadID: UUID? = nil,
         timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.leadID = leadID
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

enum EventType: String, Codable {
    case companyFound, contactFound, emailVerified
    case emailDrafted, emailApproved, emailSent, emailOpened
    case replyReceived, followUpDrafted, followUpSent
    case leadConverted, leadLost, unsubscribed
    case campaignStarted, campaignCompleted
    case csvImported, socialPostCreated
}

struct ConversionFunnel {
    let companiesFound: Int
    let contactsFound: Int
    let emailsVerified: Int
    let emailsDrafted: Int
    let emailsSent: Int
    let repliesReceived: Int
    let followUpsSent: Int
    
    var verificationRate: Double {
        guard contactsFound > 0 else { return 0 }
        return Double(emailsVerified) / Double(contactsFound) * 100
    }
    var sendRate: Double {
        guard emailsDrafted > 0 else { return 0 }
        return Double(emailsSent) / Double(emailsDrafted) * 100
    }
    var replyRate: Double {
        guard emailsSent > 0 else { return 0 }
        return Double(repliesReceived) / Double(emailsSent) * 100
    }
}

struct IndustryPerformance: Identifiable {
    let id = UUID()
    let industry: String
    let sent: Int
    let replies: Int
    let conversions: Int
    
    var replyRate: Double {
        guard sent > 0 else { return 0 }
        return Double(replies) / Double(sent) * 100
    }
}
