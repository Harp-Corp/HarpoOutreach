import Foundation
import SwiftUI

// MARK: - AppViewModel+Inbox
// Handles: reply checking, follow-up drafting/approving/sending
// Features:
//   Task 8:  Batch limit - sendAllFollowUps() capped to settings.batchSize with random delay
//   Task 9:  Opt-out detection - unsubscribe keywords to DatabaseService.shared.addToBlocklist()
//   Task 10: Configurable sender - settings.senderEmail
//   Thread-based reply detection: checkRepliesViaThreads() uses Gmail Threads API
//   Unsubscribe detection: uses GmailService.detectsUnsubscribe() which only checks reply portion

extension AppViewModel {

    // MARK: - Check for Replies (primary: thread-based, fallback: subject-based)
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

                // Detect unsubscribe — use GmailService.detectsUnsubscribe which only checks
                // the reply portion (not quoted original), avoiding false positives from our footer
                let isUnsubscribe = gmailService.detectsUnsubscribe(in: reply.body)

                // Detect bounce indicators
                let bodyLower = reply.body.lowercased()
                let subjectLower = reply.subject.lowercased()
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
                    if isUnsubscribe {
                        // Add to blocklist for unsubscribe
                        db.addToBlocklist(email: leads[idx].email, reason: "Unsubscribe reply received")
                        leads[idx].status = .doNotContact
                        leads[idx].optedOut = true
                        leads[idx].replyReceived = "[UNSUBSCRIBE] \(String(reply.snippet.prefix(200)))"
                    } else if isBounce {
                        leads[idx].deliveryStatus = .bounced
                        leads[idx].replyReceived = "BOUNCE: \(reply.snippet)"
                    } else {
                        if leads[idx].replyReceived.isEmpty {
                            leads[idx].status = .replied
                        }
                        leads[idx].replyReceived = String(reply.body.prefix(1000))
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

    // MARK: - Thread-based Reply Detection (primary method, mirrors web check-replies)
    /// Checks replies by fetching each Gmail thread directly via Threads API.
    /// More reliable than subject-based search — matches the exact conversation.
    func checkRepliesViaThreads() async {
        // Collect all leads that have a stored gmailThreadId
        let leadsWithThreads = leads.filter { !$0.gmailThreadId.isEmpty && $0.dateEmailSent != nil }

        guard !leadsWithThreads.isEmpty else {
            // No thread IDs available — fall back to subject-based method
            await checkForReplies()
            return
        }

        isLoading = true
        currentStep = "Checking \(leadsWithThreads.count) email threads for replies..."

        let threadIds: [(leadId: UUID, threadId: String)] = leadsWithThreads.map {
            (leadId: $0.id, threadId: $0.gmailThreadId)
        }

        do {
            let threadReplies = try await gmailService.checkRepliesViaThreads(threadIds: threadIds)

            var repliesFound = 0
            var unsubscribesFound = 0

            for threadReply in threadReplies {
                guard let idx = leads.firstIndex(where: { $0.id == threadReply.leadId }) else { continue }

                let msg = threadReply.message

                // Detect unsubscribe — GmailService.detectsUnsubscribe only checks the reply
                // portion (before quoted sections), avoiding false positives from our footer
                let isUnsubscribe = gmailService.detectsUnsubscribe(in: msg.body)

                // Detect bounce
                let bodyLower = msg.body.lowercased()
                let subjectLower = msg.subject.lowercased()
                let isBounce = bodyLower.contains("delivery failed")
                    || bodyLower.contains("mailer-daemon")
                    || bodyLower.contains("undeliverable")
                    || bodyLower.contains("does not exist")
                    || bodyLower.contains("no such user")
                    || subjectLower.contains("delivery status notification")
                    || subjectLower.contains("undeliverable")

                if isUnsubscribe {
                    db.addToBlocklist(email: leads[idx].email, reason: "Unsubscribe-Antwort")
                    leads[idx].status = .doNotContact
                    leads[idx].optedOut = true
                    leads[idx].optOutDate = Date()
                    leads[idx].replyReceived = "[UNSUBSCRIBE] \(String(msg.snippet.prefix(200)))"
                    unsubscribesFound += 1
                    print("[Inbox] Thread unsubscribe from \(leads[idx].email)")
                } else if isBounce {
                    leads[idx].deliveryStatus = .bounced
                    leads[idx].replyReceived = "BOUNCE: \(msg.snippet)"
                    print("[Inbox] Bounce detected for \(leads[idx].email)")
                } else {
                    if leads[idx].replyReceived.isEmpty {
                        leads[idx].status = .replied
                    }
                    leads[idx].replyReceived = String(msg.body.prefix(1000))
                    repliesFound += 1
                    print("[Inbox] Thread reply from \(leads[idx].email)")
                }

                if !settings.spreadsheetID.isEmpty {
                    try? await sheetsService.logReplyReceived(
                        spreadsheetID: settings.spreadsheetID,
                        lead: leads[idx],
                        replySubject: msg.subject,
                        replySnippet: msg.snippet,
                        replyFrom: msg.from
                    )
                }
            }

            saveLeads()

            // Also update the replies array for UI display
            replies = threadReplies.map { $0.message }

            currentStep = "\(repliesFound) replies, \(unsubscribesFound) unsubscribes found"
            print("[Inbox] checkRepliesViaThreads: \(repliesFound) replies, \(unsubscribesFound) unsubscribes")

            // If there are leads without a thread ID, also run the legacy subject-based check
            let leadsWithoutThreads = leads.filter {
                $0.gmailThreadId.isEmpty
                && ($0.dateEmailSent != nil || $0.dateFollowUpSent != nil)
            }
            if !leadsWithoutThreads.isEmpty {
                print("[Inbox] \(leadsWithoutThreads.count) leads without thread IDs — running fallback subject search")
                await checkForRepliesLegacy()
            }

        } catch {
            errorMessage = "Thread reply check failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Legacy subject-based reply check — used as fallback for leads without gmailThreadId.
    /// Mirrors the original checkForReplies() logic but does not overwrite data for
    /// leads that already have a thread-based reply.
    private func checkForRepliesLegacy() async {
        let sentLeads = leads.filter { $0.dateEmailSent != nil || $0.dateFollowUpSent != nil }
        var sentSubjects: [String] = []
        for lead in sentLeads {
            if let subj = lead.draftedEmail?.subject, !subj.isEmpty { sentSubjects.append(subj) }
            if let subj = lead.followUpEmail?.subject, !subj.isEmpty { sentSubjects.append(subj) }
        }
        let uniqueSubjects = Array(Set(sentSubjects))
        let sentLeadEmails = sentLeads.map { $0.email }
        guard !uniqueSubjects.isEmpty else { return }

        do {
            let found = try await gmailService.checkReplies(
                sentSubjects: uniqueSubjects,
                leadEmails: sentLeadEmails
            )
            for reply in found {
                let replyFrom = reply.from.lowercased()
                let replySubject = reply.subject.lowercased()
                    .replacingOccurrences(of: "re: ", with: "")
                    .replacingOccurrences(of: "aw: ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Only process leads that don't have a thread ID (avoid overwriting thread data)
                guard let idx = leads.firstIndex(where: { lead in
                    lead.gmailThreadId.isEmpty
                    && !lead.email.isEmpty
                    && replyFrom.contains(lead.email.lowercased())
                    && (lead.dateEmailSent != nil || lead.dateFollowUpSent != nil)
                }) else { continue }

                let isUnsubscribe = gmailService.detectsUnsubscribe(in: reply.body)
                let bodyLower = reply.body.lowercased()
                let isBounce = bodyLower.contains("delivery failed")
                    || bodyLower.contains("mailer-daemon")
                    || bodyLower.contains("undeliverable")

                if isUnsubscribe {
                    db.addToBlocklist(email: leads[idx].email, reason: "Unsubscribe reply received")
                    leads[idx].status = .doNotContact
                    leads[idx].optedOut = true
                    leads[idx].replyReceived = "[UNSUBSCRIBE] \(String(reply.snippet.prefix(200)))"
                } else if isBounce {
                    leads[idx].deliveryStatus = .bounced
                    leads[idx].replyReceived = "BOUNCE: \(reply.snippet)"
                } else {
                    if leads[idx].replyReceived.isEmpty { leads[idx].status = .replied }
                    leads[idx].replyReceived = String(reply.body.prefix(1000))
                }
            }
            saveLeads()
        } catch {
            print("[Inbox] Legacy reply check error: \(error.localizedDescription)")
        }
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

        // Opt-out check
        if db.isBlocked(email: leads[idx].email) {
            errorMessage = "\(leads[idx].email) is on the opt-out blocklist."
            leads[idx].status = .doNotContact
            leads[idx].optedOut = true
            saveLeads()
            return
        }

        // Scheduling check
        if let scheduledDate = leads[idx].scheduledSendDate, scheduledDate > Date() {
            statusMessage = "Follow-up to \(leads[idx].name) is scheduled for \(scheduledDate.formatted()). Skipping."
            return
        }

        isLoading = true; currentStep = "Sending follow-up to \(leads[idx].email)..."
        do {
            _ = try await gmailService.sendEmail(
                to: leads[idx].email,
                from: settings.senderEmail,
                subject: followUp.subject,
                body: followUp.body
            )
            leads[idx].dateFollowUpSent = Date()
            leads[idx].followUpEmail?.sentDate = Date()
            leads[idx].status = .followUpSent
            leads[idx].deliveryStatus = .delivered
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
            leads[idx].deliveryStatus = .failed
            saveLeads()
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Send All Follow-Ups - Batch Limited
    func sendAllFollowUps() async {
        let ready = leads.filter {
            $0.followUpEmail?.isApproved == true
            && $0.dateFollowUpSent == nil
            && !$0.optedOut
        }
        guard !ready.isEmpty else { statusMessage = "No approved follow-ups to send."; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }

        // Cap to batchSize
        let batch = Array(ready.prefix(settings.batchSize))
        isLoading = true
        var sentCount = 0
        var skippedOptOut = 0
        var skippedScheduled = 0

        for (index, lead) in batch.enumerated() {
            currentStep = "Sending follow-up \(sentCount + 1)/\(batch.count) to \(lead.name)..."

            // Opt-out check
            if db.isBlocked(email: lead.email) {
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].status = .doNotContact
                    leads[idx].optedOut = true
                    saveLeads()
                }
                skippedOptOut += 1
                continue
            }

            // Scheduling check
            if let scheduledDate = lead.scheduledSendDate, scheduledDate > Date() {
                skippedScheduled += 1
                continue
            }

            do {
                guard let followUp = lead.followUpEmail else { continue }
                _ = try await gmailService.sendEmail(
                    to: lead.email,
                    from: settings.senderEmail,
                    subject: followUp.subject,
                    body: followUp.body
                )
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].dateFollowUpSent = Date()
                    leads[idx].followUpEmail?.sentDate = Date()
                    leads[idx].status = .followUpSent
                    leads[idx].deliveryStatus = .delivered
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

                // Random delay 30-90 seconds between sends
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
