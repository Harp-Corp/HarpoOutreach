import Foundation
import SwiftUI

// MARK: - AppViewModel+Inbox
// Handles: reply checking, follow-up drafting/approving/sending
// Features:
//   Task 8:  Batch limit - sendAllFollowUps() capped to settings.batchSize with random delay
//   Task 9:  Opt-out detection - unsubscribe keywords to DatabaseService.shared.addToBlocklist()
//   Task 10: Configurable sender - settings.senderEmail

extension AppViewModel {

    // MARK: - Check for Replies (task 9: opt-out detection)
    func checkForReplies() async {
        var sentSubjects: [String] = []
        for lead in leads {
            if lead.dateEmailSent != nil, let subj = lead.draftedEmail?.subject, !subj.isEmpty {
                sentSubjects.append(subj)
            }
            if lead.dateFollowUpSent != nil, let subj = lead.followUpEmail?.subject, !subj.isEmpty {
                sentSubjects.append(subj)
            }
        }
        let uniqueSubjects = Array(Set(sentSubjects))
        let sentLeadEmails = leads
            .filter { $0.dateEmailSent != nil || $0.dateFollowUpSent != nil }
            .map { $0.email }

        guard !uniqueSubjects.isEmpty else { statusMessage = "No sent emails to check."; return }
        isLoading = true; currentStep = "Checking inbox for replies..."

        do {
            let found = try await gmailService.checkReplies(
                sentSubjects: uniqueSubjects,
                leadEmails: sentLeadEmails
            )
            replies = found

            for reply in found {
                let replyFrom = reply.from.lowercased()
                let replySubject = reply.subject.lowercased()
                    .replacingOccurrences(of: "re: ", with: "")
                    .replacingOccurrences(of: "aw: ", with: "")
                    .replacingOccurrences(of: "fwd: ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Task 9: Detect unsubscribe intent
                let bodyLower = reply.body.lowercased()
                let subjectLower = reply.subject.lowercased()
                let isUnsubscribe = bodyLower.contains("unsubscribe")
                    || bodyLower.contains("abmelden")
                    || bodyLower.contains("austragen")
                    || bodyLower.contains("opt out")
                    || bodyLower.contains("opt-out")
                    || subjectLower.contains("unsubscribe")
                    || subjectLower.contains("abmelden")

                // Task 7: Detect bounce indicators
                let isBounce = bodyLower.contains("delivery failed")
                    || bodyLower.contains("mailer-daemon")
                    || bodyLower.contains("undeliverable")
                    || bodyLower.contains("does not exist")
                    || bodyLower.contains("no such user")
                    || subjectLower.contains("delivery status notification")
                    || subjectLower.contains("undeliverable")

                // Match reply to a lead by subject or email
                var matchedIdx: Int?
                matchedIdx = leads.firstIndex(where: { lead in
                    if let draftSubj = lead.draftedEmail?.subject, !draftSubj.isEmpty {
                        let cleanDraft = draftSubj.lowercased()
                            .replacingOccurrences(of: "re: ", with: "")
                            .replacingOccurrences(of: "aw: ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if replySubject.contains(cleanDraft) || cleanDraft.contains(replySubject) { return true }
                        let draftWords = Set(cleanDraft.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        let replyWords = Set(replySubject.components(separatedBy: .whitespaces).filter { $0.count > 3 })
                        if !draftWords.isEmpty && Double(draftWords.intersection(replyWords).count) / Double(draftWords.count) > 0.5 { return true }
                    }
                    if let fuSubj = lead.followUpEmail?.subject, !fuSubj.isEmpty {
                        let cleanFU = fuSubj.lowercased()
                            .replacingOccurrences(of: "re: ", with: "")
                            .replacingOccurrences(of: "aw: ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if replySubject.contains(cleanFU) || cleanFU.contains(replySubject) { return true }
                    }
                    return false
                })
                if matchedIdx == nil {
                    matchedIdx = leads.firstIndex(where: { lead in
                        !lead.email.isEmpty
                        && replyFrom.contains(lead.email.lowercased())
                        && (lead.dateEmailSent != nil || lead.dateFollowUpSent != nil)
                    })
                }

                if let idx = matchedIdx {
                    // Task 9: Add to blocklist if unsubscribe detected
                    if isUnsubscribe {
                        DatabaseService.shared.addToBlocklist(email: leads[idx].email, reason: "Unsubscribe reply received")
                        leads[idx].status = .doNotContact
                        leads[idx].optedOut = true
                        leads[idx].replyReceived = reply.snippet
                    } else if isBounce {
                        // Task 7: Mark bounced
                        leads[idx].deliveryStatus = .bounced
                        leads[idx].replyReceived = "BOUNCE: \(reply.snippet)"
                    } else {
                        leads[idx].replyReceived = reply.snippet
                        leads[idx].status = .replied
                    }

                    if !settings.spreadsheetID.isEmpty {
                        try? await sheetsService.logReplyReceived(
                            spreadsheetID: settings.spreadsheetID,
                            lead: leads[idx],
                            replySubject: reply.subject,
                            replySnippet: reply.snippet,
                            replyFrom: reply.from
                        )
                    }
                }
            }

            saveLeads()
            currentStep = "\(found.count) replies found"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Check Follow-Ups Needed (14-day threshold)
    func checkFollowUpsNeeded() -> [Lead] {
        let calendar = Calendar.current
        return leads.filter { lead in
            guard lead.status == .emailSent,
                  let sentDate = lead.dateEmailSent,
                  lead.replyReceived.isEmpty,
                  lead.followUpEmail == nil,
                  !lead.optedOut else { return false }
            return (calendar.dateComponents([.day], from: sentDate, to: Date()).day ?? 0) >= 14
        }
    }

    // MARK: - Draft Follow-Up
    func draftFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let originalEmail = leads[idx].draftedEmail else { return }
        isLoading = true; currentStep = "Creating follow-up for \(leads[idx].name)..."
        do {
            let followUp = try await pplxService.draftFollowUp(
                lead: leads[idx],
                originalEmail: originalEmail.body,
                followUpEmail: leads[idx].followUpEmail?.body ?? "",
                replyReceived: leads[idx].replyReceived,
                senderName: settings.senderName,
                apiKey: settings.perplexityAPIKey
            )
            leads[idx].followUpEmail = followUp
            leads[idx].status = .followUpDrafted
            saveLeads()
            currentStep = "Follow-up created for \(leads[idx].name)"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Draft Follow-Up from Contact view
    func draftFollowUpFromContact(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        let lead = leads[idx]
        guard lead.dateEmailSent != nil else { errorMessage = "Send an email first."; return }
        if lead.followUpEmail != nil {
            statusMessage = "Follow-up draft already exists for \(lead.name)."
            return
        }
        guard let originalEmail = lead.draftedEmail else {
            errorMessage = "No original draft for \(lead.name)"
            return
        }
        isLoading = true; currentStep = "Creating follow-up for \(lead.name)..."
        do {
            let followUp = try await pplxService.draftFollowUp(
                lead: lead,
                originalEmail: originalEmail.body,
                followUpEmail: lead.followUpEmail?.body ?? "",
                replyReceived: lead.replyReceived,
                senderName: settings.senderName,
                apiKey: settings.perplexityAPIKey
            )
            leads[idx].followUpEmail = followUp
            leads[idx].status = .followUpDrafted
            saveLeads()
            currentStep = "Follow-up created for \(leads[idx].name)"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Approve Follow-Up
    func approveFollowUp(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].followUpEmail?.isApproved = true
        saveLeads()
    }

    // MARK: - Send Follow-Up (single)
    func sendFollowUp(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let followUp = leads[idx].followUpEmail, followUp.isApproved else {
            errorMessage = "Follow-up must be approved first."; return
        }

        // Task 9: Opt-out check
        if DatabaseService.shared.isBlocked(email: leads[idx].email) {
            errorMessage = "\(leads[idx].email) is on the opt-out blocklist."
            leads[idx].status = .doNotContact
            leads[idx].optedOut = true
            saveLeads()
            return
        }

        // Task 5: Scheduling check
        if let scheduledDate = leads[idx].scheduledSendDate, scheduledDate > Date() {
            statusMessage = "Follow-up to \(leads[idx].name) is scheduled for \(scheduledDate.formatted()). Skipping."
            return
        }

        isLoading = true; currentStep = "Sending follow-up to \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email,
                from: settings.senderEmail,    // Task 10
                subject: followUp.subject,
                body: followUp.body
            )
            leads[idx].dateFollowUpSent = Date()
            leads[idx].followUpEmail?.sentDate = Date()
            leads[idx].status = .followUpSent
            leads[idx].deliveryStatus = .delivered  // Task 7
            saveLeads()

            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.logEmailEvent(
                    spreadsheetID: settings.spreadsheetID,
                    lead: leads[idx],
                    emailType: "Follow-Up",
                    subject: followUp.subject,
                    body: followUp.body,
                    summary: "Follow-up to \(leads[idx].name) (\(leads[idx].company))"
                )
            }
            currentStep = "Follow-up sent to \(leads[idx].email)"
        } catch {
            leads[idx].deliveryStatus = .failed  // Task 7
            saveLeads()
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Send All Follow-Ups - Batch Limited (task 8)
    func sendAllFollowUps() async {
        let ready = leads.filter {
            $0.followUpEmail?.isApproved == true
            && $0.dateFollowUpSent == nil
            && !$0.optedOut
        }
        guard !ready.isEmpty else { statusMessage = "No approved follow-ups to send."; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }

        // Task 8: Cap to batchSize
        let batch = Array(ready.prefix(settings.batchSize))
        isLoading = true
        var sentCount = 0
        var skippedOptOut = 0
        var skippedScheduled = 0

        for (index, lead) in batch.enumerated() {
            currentStep = "Sending follow-up \(sentCount + 1)/\(batch.count) to \(lead.name)..."

            // Task 9: Opt-out check
            if DatabaseService.shared.isBlocked(email: lead.email) {
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].status = .doNotContact
                    leads[idx].optedOut = true
                    saveLeads()
                }
                skippedOptOut += 1
                continue
            }

            // Task 5: Scheduling check
            if let scheduledDate = lead.scheduledSendDate, scheduledDate > Date() {
                skippedScheduled += 1
                continue
            }

            do {
                guard let followUp = lead.followUpEmail else { continue }
                _ = try await gmailService.sendEmail(
                    to: lead.email,
                    from: settings.senderEmail,    // Task 10
                    subject: followUp.subject,
                    body: followUp.body
                )
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].dateFollowUpSent = Date()
                    leads[idx].followUpEmail?.sentDate = Date()
                    leads[idx].status = .followUpSent
                    leads[idx].deliveryStatus = .delivered  // Task 7
                    saveLeads()
                    if !settings.spreadsheetID.isEmpty {
                        try? await sheetsService.logEmailEvent(
                            spreadsheetID: settings.spreadsheetID,
                            lead: leads[idx],
                            emailType: "Follow-Up",
                            subject: followUp.subject,
                            body: followUp.body,
                            summary: "Follow-up to \(lead.name) (\(lead.company))"
                        )
                    }
                }
                sentCount += 1

                // Task 8: Random delay 30-90 seconds between sends
                if index < batch.count - 1 {
                    let delay = UInt64.random(in: 30_000_000_000...90_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            } catch { }
        }

        isLoading = false; currentStep = ""
        let remaining = ready.count - batch.count
        var msg = "\(sentCount) follow-ups sent."
        if remaining > 0 { msg += " \(remaining) remaining in queue." }
        if skippedOptOut > 0 { msg += " \(skippedOptOut) skipped (opted out)." }
        if skippedScheduled > 0 { msg += " \(skippedScheduled) skipped (scheduled)." }
        statusMessage = msg
    }

    // MARK: - Follow-Up Draft Management
    func updateFollowUpDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = OutboundEmail(
                id: lead.followUpEmail?.id ?? UUID(),
                subject: subject,
                body: body,
                isApproved: true
            )
            saveLeads()
            statusMessage = "Follow-up draft for \(lead.name) updated"
        }
    }

    func deleteFollowUpDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].followUpEmail = nil
            leads[index].status = .emailSent
            saveLeads()
            statusMessage = "Follow-up draft for \(lead.name) deleted"
        }
    }
}
