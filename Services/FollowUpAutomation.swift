import Foundation

// MARK: - FollowUpAutomation
// Verbesserung 6: Automatische Follow-Up Erkennung und Drafting
// Prueft regelmaessig ob Follow-Ups faellig sind
@MainActor
class FollowUpAutomation: ObservableObject {
    
    @Published var pendingFollowUps: [FollowUpCandidate] = []
    @Published var isRunning = false
    
    private var timer: Timer?
    
    // MARK: - Configuration
    struct Config {
        var initialFollowUpDays: Int = 14    // Days after first email
        var secondFollowUpDays: Int = 28     // Days after first email
        var maxFollowUps: Int = 2            // Maximum follow-ups per lead
        var excludeReplied: Bool = true      // Skip leads that replied
        var excludeUnsubscribed: Bool = true // Skip do-not-contact
        var autoDraft: Bool = false          // Auto-create drafts
    }
    
    var config = Config()
    
    // MARK: - Scan for Follow-Up Candidates
    func scanForFollowUps(leads: [Lead]) -> [FollowUpCandidate] {
        let calendar = Calendar.current
        let now = Date()
        var candidates: [FollowUpCandidate] = []
        
        for lead in leads {
            // Skip if not sent yet
            guard let sentDate = lead.dateEmailSent else { continue }
            
            // Skip if replied
            if config.excludeReplied && !lead.replyReceived.isEmpty { continue }
            
            // Skip if do-not-contact
            if config.excludeUnsubscribed && lead.status == .doNotContact { continue }
            
            // Skip if already sent follow-up
            if lead.dateFollowUpSent != nil { continue }
            
            let daysSinceSent = calendar.dateComponents([.day], from: sentDate, to: now).day ?? 0
            
            // First follow-up check
            if lead.followUpEmail == nil && daysSinceSent >= config.initialFollowUpDays {
                candidates.append(FollowUpCandidate(
                    leadID: lead.id,
                    leadName: lead.name,
                    company: lead.company,
                    daysSinceSent: daysSinceSent,
                    followUpNumber: 1,
                    priority: calculatePriority(daysSinceSent: daysSinceSent, lead: lead)
                ))
            }
        }
        
        // Sort by priority (highest first)
        candidates.sort { $0.priority > $1.priority }
        pendingFollowUps = candidates
        return candidates
    }
    
    // MARK: - Auto-scan timer
    func startAutoScan(leads: [Lead], interval: TimeInterval = 3600) {
        stopAutoScan()
        isRunning = true
        _ = scanForFollowUps(leads: leads)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.scanForFollowUps(leads: leads)
            }
        }
    }
    
    func stopAutoScan() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    // MARK: - Priority Calculation
    private func calculatePriority(daysSinceSent: Int, lead: Lead) -> Int {
        var priority = 50
        
        // More overdue = higher priority
        if daysSinceSent > 21 { priority += 20 }
        else if daysSinceSent > 14 { priority += 10 }
        
        // Verified email = higher priority
        if lead.emailVerified { priority += 10 }
        
        // Has LinkedIn = higher priority (can cross-reference)
        if !lead.linkedInURL.isEmpty { priority += 5 }
        
        return min(100, priority)
    }
    
    // MARK: - Batch operations
    func draftAllPending(vm: AppViewModel) async -> Int {
        var count = 0
        for candidate in pendingFollowUps {
            await vm.draftFollowUp(for: candidate.leadID)
            count += 1
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return count
    }
}

// MARK: - Models
struct FollowUpCandidate: Identifiable {
    let id = UUID()
    let leadID: UUID
    let leadName: String
    let company: String
    let daysSinceSent: Int
    let followUpNumber: Int
    let priority: Int
    
    var urgencyLevel: UrgencyLevel {
        if daysSinceSent > 28 { return .high }
        if daysSinceSent > 21 { return .medium }
        return .normal
    }
}

enum UrgencyLevel: String {
    case normal = "Normal"
    case medium = "Medium"
    case high = "High"
    
    var color: String {
        switch self {
        case .normal: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}
