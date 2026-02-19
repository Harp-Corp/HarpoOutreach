import Foundation

class NewsletterService {
    
    private let gmailService: GmailService
    private let sheetsService: GoogleSheetsService
    
    init(gmailService: GmailService, sheetsService: GoogleSheetsService) {
        self.gmailService = gmailService
        self.sheetsService = sheetsService
    }
    
    // MARK: - Build Recipient List
    func buildRecipientList(from leads: [Lead], industries: [String], regions: [String]) -> [Lead] {
        return leads.filter { lead in
            // Exclude unsubscribed leads
            guard !lead.unsubscribed else { return false }
            // Exclude leads marked as do-not-contact
            guard lead.status != .doNotContact else { return false }
            // Must have a verified email
            guard lead.emailVerified && !lead.email.isEmpty else { return false }
            // Filter by industry if specified
            if !industries.isEmpty {
                // Lead's company industry must match one of the target industries
                let matchesIndustry = industries.contains(where: { lead.company.lowercased().contains($0.lowercased()) })
                if !matchesIndustry { return false }
            }
            return true
        }
    }
    
    // MARK: - Send Newsletter Campaign
    func sendCampaign(campaign: NewsletterCampaign, recipients: [Lead], accessToken: String, senderEmail: String) async throws -> NewsletterCampaign {
        var updatedCampaign = campaign
        updatedCampaign.status = .sending
        updatedCampaign.recipientCount = recipients.count
        
        var sentCount = 0
        var bounceCount = 0
        
        for lead in recipients {
            do {
                // Personalize the HTML body
                let personalizedHTML = personalizeContent(
                    html: campaign.htmlBody,
                    lead: lead,
                    unsubscribeURL: "https://new.harpocrates-corp.com/unsubscribe?email=\(lead.email)"
                )
                
                try await gmailService.sendEmail(
                    to: lead.email,
                    subject: campaign.subject,
                    htmlBody: personalizedHTML,
                    accessToken: accessToken,
                    from: senderEmail
                )
                sentCount += 1
                
                // Small delay between sends to avoid rate limits
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                bounceCount += 1
            }
        }
        
        updatedCampaign.sentCount = sentCount
        updatedCampaign.bounceCount = bounceCount
        updatedCampaign.status = .sent
        updatedCampaign.sentDate = Date()
        
        return updatedCampaign
    }
    
    // MARK: - Personalize Newsletter Content
    func personalizeContent(html: String, lead: Lead, unsubscribeURL: String) -> String {
        var personalized = html
        personalized = personalized.replacingOccurrences(of: "{{FIRST_NAME}}", with: lead.name.components(separatedBy: " ").first ?? lead.name)
        personalized = personalized.replacingOccurrences(of: "{{FULL_NAME}}", with: lead.name)
        personalized = personalized.replacingOccurrences(of: "{{COMPANY}}", with: lead.company)
        personalized = personalized.replacingOccurrences(of: "{{TITLE}}", with: lead.title)
        personalized = personalized.replacingOccurrences(of: "{{UNSUBSCRIBE_URL}}", with: unsubscribeURL)
        return personalized
    }
    
    // MARK: - Track Campaign in Google Sheets
    func trackCampaign(campaign: NewsletterCampaign, accessToken: String, spreadsheetID: String) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        let row: [String] = [
            campaign.id.uuidString,
            campaign.name,
            campaign.subject,
            dateFormatter.string(from: campaign.createdDate),
            campaign.sentDate.map { dateFormatter.string(from: $0) } ?? "",
            "\(campaign.recipientCount)",
            "\(campaign.sentCount)",
            "\(campaign.openCount)",
            "\(campaign.clickCount)",
            "\(campaign.unsubscribeCount)",
            "\(campaign.bounceCount)",
            campaign.status.rawValue,
            campaign.targetIndustries.joined(separator: ", "),
            campaign.targetRegions.joined(separator: ", ")
        ]
        
        try await sheetsService.appendRow(
            row: row,
            sheet: "Newsletter_Campaigns",
            accessToken: accessToken,
            spreadsheetID: spreadsheetID
        )
    }
    
    // MARK: - Handle Unsubscribe
    func processUnsubscribe(email: String, leads: inout [Lead]) {
        if let index = leads.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
            leads[index].unsubscribed = true
            leads[index].unsubscribedDate = Date()
        }
    }
}

// MARK: - Newsletter Error
enum NewsletterError: LocalizedError {
    case noRecipients
    case sendingFailed(message: String)
    case campaignNotReady
    
    var errorDescription: String? {
        switch self {
        case .noRecipients: return "No eligible recipients found for this campaign"
        case .sendingFailed(let msg): return "Newsletter sending failed: \(msg)"
        case .campaignNotReady: return "Campaign is not ready to send"
        }
    }
}
