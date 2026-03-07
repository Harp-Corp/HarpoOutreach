import Foundation
import SwiftUI

// MARK: - AppViewModel+EmailPipeline
// Handles: drafting, approving, sending emails (initial outreach)
// Features:
//   Task 5:  Scheduling - skip leads with scheduledSendDate in the future
//   Task 7:  Delivery tracking - update deliveryStatus after send
//   Task 8:  Batch limit - sendAllApproved() capped to settings.batchSize with random 30-90s delays
//   Task 9:  Opt-out check - DatabaseService.shared.isBlocked() before every send
//   Task 10: Configurable sender - settings.senderEmail instead of static constant
//   Task 13: Dynamic subject alternatives - generate 3 subjects and pick best
//   Reset/Resend: Full and soft reset matching web app /reset/{lead_id} and /resend/{lead_id}
//   Thread ID: Store gmailThreadId returned from sendEmail

extension AppViewModel {

    // MARK: - 4+5) Research + Draft Email (with dynamic subject generation and generic fallback)
    func draftEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        // Skip leads with no email address (unless manually created)
        guard !leads[idx].email.isEmpty || leads[idx].isManuallyCreated else {
            print("[EmailPipeline] Skipping draft for \(leads[idx].name) - no email address")
            return
        }
        isLoading = true; currentStep = "Researching challenges for \(leads[idx].company)..."
        do {
            let companyForResearch = companies.first {
                $0.name.lowercased() == leads[idx].company.lowercased()
            } ?? Company(name: leads[idx].company, industry: "", region: "")

            // Step 1: Research challenges with generic fallback (mirrors web draft_email)
            let challenges: String
            do {
                let rawChallenges = try await pplxService.researchChallenges(
                    company: companyForResearch, apiKey: settings.perplexityAPIKey
                )
                // Use generic fallback if Perplexity returned a no-info response
                if PerplexityService.isUnknownCompany(rawChallenges) {
                    print("[EmailPipeline] Unknown company '\(leads[idx].company)', using generic fallback")
                    challenges = PerplexityService.genericComplianceChallenges(
                        companyName: leads[idx].company,
                        industry: companyForResearch.industry
                    )
                } else {
                    challenges = rawChallenges
                }
            } catch {
                print("[EmailPipeline] Challenge research failed for \(leads[idx].company): \(error.localizedDescription), using generic fallback")
                challenges = PerplexityService.genericComplianceChallenges(
                    companyName: leads[idx].company,
                    industry: companyForResearch.industry
                )
            }

            currentStep = "Creating personalized email for \(leads[idx].name)..."
            var email = try await pplxService.draftEmail(
                lead: leads[idx],
                challenges: challenges,
                senderName: settings.senderName,
                apiKey: settings.perplexityAPIKey
            )

            // Step 2: Generate dynamic subject alternatives and use the best one
            currentStep = "Generating subject alternatives for \(leads[idx].company)..."
            if let bestSubject = await generateBestSubject(
                company: leads[idx].company,
                industry: companyForResearch.industry,
                emailBodyPreview: String(email.body.prefix(200))
            ) {
                email = OutboundEmail(
                    id: email.id,
                    subject: bestSubject,
                    body: email.body,
                    isApproved: email.isApproved,
                    sentDate: email.sentDate
                )
            }

            leads[idx].draftedEmail = email
            leads[idx].status = .emailDrafted
            saveLeads()
            currentStep = "Email draft created for \(leads[idx].name)"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Ask Perplexity for 3 subject alternatives, return the first one.
    private func generateBestSubject(company: String, industry: String, emailBodyPreview: String) async -> String? {
        let prompt = """
        Generate 3 different email subject lines for a cold outreach email to \(company) about compliance/RegTech.
        The email body is about: \(emailBodyPreview)
        Industry context: \(industry.isEmpty ? "regulated enterprise" : industry)
        Return ONLY 3 subjects, one per line. No numbering, no explanation.
        """
        guard let raw = try? await pplxService.rawGenerate(prompt: prompt, apiKey: settings.perplexityAPIKey) else {
            return nil
        }
        let lines = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.first
    }

    func draftAllEmails() async {
        // Draft for all leads that have an email address (or are manually created)
        let toDraft = leads.filter({ (!$0.email.isEmpty || $0.isManuallyCreated) && $0.draftedEmail == nil })
        var created = 0
        var failed = 0
        for lead in toDraft {
            do {
                await draftEmail(for: lead.id)
                if leads.first(where: { $0.id == lead.id })?.draftedEmail != nil {
                    created += 1
                } else {
                    failed += 1
                }
            } catch {
                print("[EmailPipeline] Draft failed for \(lead.name): \(error.localizedDescription)")
                failed += 1
            }
        }
        if failed > 0 {
            print("[EmailPipeline] Drafts: \(created) created, \(failed) failed of \(toDraft.count) total")
        }
    }

    // MARK: - 5) Approve Email
    func approveEmail(for leadID: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        leads[idx].draftedEmail?.isApproved = true
        leads[idx].status = .emailApproved
        saveLeads()
    }

    func approveAllEmails() {
        var count = 0
        for i in leads.indices {
            if leads[i].draftedEmail != nil && leads[i].draftedEmail?.isApproved == false {
                leads[i].draftedEmail?.isApproved = true
                leads[i].status = .emailApproved
                count += 1
            }
        }
        saveLeads()
        statusMessage = "\(count) emails approved"
    }

    // MARK: - Draft Management
    func updateDraft(for lead: Lead, subject: String, body: String) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = OutboundEmail(
                id: lead.draftedEmail?.id ?? UUID(),
                subject: subject,
                body: body,
                isApproved: true
            )
            saveLeads()
            statusMessage = "Draft for \(lead.name) updated"
        }
    }

    func deleteDraft(for lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].draftedEmail = nil
            leads[index].status = .identified
            saveLeads()
            statusMessage = "Draft for \(lead.name) deleted"
        }
    }

    // MARK: - Campaign Reset (Full Reset — mirrors web /email/reset/{lead_id})
    /// Full reset: clears draft, send date, thread ID, delivery status, blocklist entry, opted_out.
    func resetLead(id: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == id }) else { return }
        leads[idx].draftedEmail = nil
        leads[idx].dateEmailSent = nil
        leads[idx].deliveryStatus = .pending
        leads[idx].gmailThreadId = ""
        leads[idx].replyReceived = ""
        leads[idx].optedOut = false
        leads[idx].optOutDate = nil
        leads[idx].status = .identified
        // Remove from blocklist if present
        if !leads[idx].email.isEmpty {
            db.removeFromBlocklist(email: leads[idx].email)
        }
        saveLeads()
        print("[EmailPipeline] Lead \(id) (\(leads[idx].name)) full campaign reset (incl. blocklist)")
        statusMessage = "\(leads[idx].name) has been fully reset."
    }

    // MARK: - Resend (Soft Reset — mirrors web /email/resend/{lead_id})
    /// Soft reset for re-sending: keeps draft+approval, only clears send date/thread/reply/blocklist.
    func resendLead(id: UUID) {
        guard let idx = leads.firstIndex(where: { $0.id == id }) else { return }
        guard leads[idx].draftedEmail != nil else {
            errorMessage = "No email draft found. Please create a draft first."
            return
        }
        leads[idx].dateEmailSent = nil
        leads[idx].deliveryStatus = .pending
        leads[idx].gmailThreadId = ""
        leads[idx].replyReceived = ""
        leads[idx].optedOut = false
        leads[idx].optOutDate = nil
        // Keep draft and approval — set status based on current approval state
        if leads[idx].draftedEmail?.isApproved == true {
            leads[idx].status = .emailApproved
        } else {
            leads[idx].status = .emailDrafted
        }
        // Remove from blocklist if present
        if !leads[idx].email.isEmpty {
            db.removeFromBlocklist(email: leads[idx].email)
        }
        saveLeads()
        print("[EmailPipeline] Lead \(id) (\(leads[idx].name)) reset for resend (draft kept, blocklist cleared)")
        statusMessage = "\(leads[idx].name) queued for resend."
    }

    // MARK: - Batch Reset (mirrors web /email/reset-batch)
    /// Full reset for multiple leads.
    func resetBatch(ids: [UUID]) {
        var resetCount = 0
        for id in ids {
            guard let idx = leads.firstIndex(where: { $0.id == id }) else { continue }
            leads[idx].draftedEmail = nil
            leads[idx].dateEmailSent = nil
            leads[idx].deliveryStatus = .pending
            leads[idx].gmailThreadId = ""
            leads[idx].replyReceived = ""
            leads[idx].optedOut = false
            leads[idx].optOutDate = nil
            leads[idx].status = .identified
            if !leads[idx].email.isEmpty {
                db.removeFromBlocklist(email: leads[idx].email)
            }
            resetCount += 1
        }
        saveLeads()
        print("[EmailPipeline] Batch reset: \(resetCount) leads (incl. blocklist)")
        statusMessage = "\(resetCount) leads fully reset."
    }

    // MARK: - Clear All Blocklist (mirrors web DELETE /data/blocklist/all)
    /// Removes ALL entries from the blocklist and resets opted_out on all leads.
    func clearAllBlocklist() {
        db.clearBlocklist()
        // Reload leads to reflect the reset opted_out flags from DB
        leads = db.loadLeads()
        statusMessage = "Blocklist cleared. All opted-out flags reset."
        print("[EmailPipeline] Entire blocklist cleared")
    }

    // MARK: - 6) Send Email (by ID)
    func sendEmail(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }),
              let email = leads[idx].draftedEmail, email.isApproved else {
            errorMessage = "Email must be approved first."; return
        }

        // Opt-out / blocklist check
        if db.isBlocked(email: leads[idx].email) {
            errorMessage = "\(leads[idx].email) is on the opt-out blocklist."
            leads[idx].status = .doNotContact
            leads[idx].optedOut = true
            saveLeads()
            return
        }

        // Scheduling check
        if let scheduledDate = leads[idx].scheduledSendDate, scheduledDate > Date() {
            statusMessage = "Email to \(leads[idx].name) is scheduled for \(scheduledDate.formatted()). Skipping."
            isLoading = false
            return
        }

        isLoading = true; currentStep = "Sending email to \(leads[idx].email)..."
        do {
            let sendResult = try await gmailService.sendEmail(
                to: leads[idx].email,
                from: settings.senderEmail,
                subject: email.subject,
                body: email.body
            )
            leads[idx].dateEmailSent = Date()
            leads[idx].draftedEmail?.sentDate = Date()
            leads[idx].status = .emailSent
            leads[idx].deliveryStatus = .delivered
            leads[idx].gmailThreadId = sendResult.threadId

            saveLeads()

            if !settings.spreadsheetID.isEmpty {
                try? await sheetsService.logEmailEvent(
                    spreadsheetID: settings.spreadsheetID,
                    lead: leads[idx],
                    emailType: "Initial",
                    subject: email.subject,
                    body: email.body,
                    summary: "Outreach to \(leads[idx].name) (\(leads[idx].company))"
                )
            }
            currentStep = "Email sent to \(leads[idx].email)"
        } catch {
            leads[idx].deliveryStatus = .failed
            saveLeads()
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - 6b) Send Email (to lead directly)
    func sendEmail(to lead: Lead) async {
        guard let draft = lead.draftedEmail else { errorMessage = "No draft for \(lead.name)"; return }
        guard !lead.email.isEmpty else { errorMessage = "No email for \(lead.name)"; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }

        // Opt-out check
        if db.isBlocked(email: lead.email) {
            errorMessage = "\(lead.email) is on the opt-out blocklist."
            if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[idx].status = .doNotContact
                leads[idx].optedOut = true
                saveLeads()
            }
            return
        }

        // Scheduling check
        if let scheduledDate = lead.scheduledSendDate, scheduledDate > Date() {
            statusMessage = "Email to \(lead.name) is scheduled for \(scheduledDate.formatted()). Skipping."
            return
        }

        isLoading = true; errorMessage = ""; currentStep = "Sending email to \(lead.name)..."
        do {
            let sendResult = try await gmailService.sendEmail(
                to: lead.email,
                from: settings.senderEmail,
                subject: draft.subject,
                body: draft.body
            )
            if let index = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[index].status = .emailSent
                leads[index].dateEmailSent = Date()
                leads[index].draftedEmail?.sentDate = Date()
                leads[index].deliveryStatus = .delivered
                leads[index].gmailThreadId = sendResult.threadId
                saveLeads()
                if !settings.spreadsheetID.isEmpty {
                    try? await sheetsService.logEmailEvent(
                        spreadsheetID: settings.spreadsheetID,
                        lead: leads[index],
                        emailType: "Initial",
                        subject: draft.subject,
                        body: draft.body,
                        summary: "Outreach to \(lead.name) (\(lead.company))"
                    )
                }
            }
            statusMessage = "Email to \(lead.name) sent"
        } catch {
            if let index = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[index].deliveryStatus = .failed
                saveLeads()
            }
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
        isLoading = false; currentStep = ""
    }

    // MARK: - 7) Send All Approved - Batch Limited
    func sendAllApproved() async {
        // Filter: approved, not sent, not opted out
        let approved = leads.filter {
            $0.draftedEmail?.isApproved == true
            && $0.dateEmailSent == nil
            && !$0.optedOut
        }
        guard !approved.isEmpty else { statusMessage = "No approved emails to send."; return }
        guard authService.isAuthenticated else { errorMessage = "Not authenticated with Google."; return }

        // Cap to batchSize (default 10)
        let batch = Array(approved.prefix(settings.batchSize))
        isLoading = true
        var sentCount = 0
        var failCount = 0
        var skippedOptOut = 0
        var skippedScheduled = 0

        for (index, lead) in batch.enumerated() {
            currentStep = "Sending \(sentCount + 1)/\(batch.count) to \(lead.name)..."

            // Opt-out / blocklist check
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
                guard let draft = lead.draftedEmail else { continue }
                let sendResult = try await gmailService.sendEmail(
                    to: lead.email,
                    from: settings.senderEmail,
                    subject: draft.subject,
                    body: draft.body
                )
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].status = .emailSent
                    leads[idx].dateEmailSent = Date()
                    leads[idx].draftedEmail?.sentDate = Date()
                    leads[idx].deliveryStatus = .delivered
                    leads[idx].gmailThreadId = sendResult.threadId
                    saveLeads()
                    if !settings.spreadsheetID.isEmpty {
                        try? await sheetsService.logEmailEvent(
                            spreadsheetID: settings.spreadsheetID,
                            lead: leads[idx],
                            emailType: "Initial",
                            subject: draft.subject,
                            body: draft.body,
                            summary: "Outreach to \(lead.name) (\(lead.company))"
                        )
                    }
                }
                sentCount += 1

                // Random delay 30-90 seconds between sends (except after last)
                if index < batch.count - 1 {
                    let delay = UInt64.random(in: 30_000_000_000...90_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            } catch {
                if let idx = leads.firstIndex(where: { $0.id == lead.id }) {
                    leads[idx].deliveryStatus = .failed
                    saveLeads()
                }
                failCount += 1
            }
        }

        isLoading = false; currentStep = ""
        let remaining = approved.count - batch.count
        var msg = "Batch: \(sentCount)/\(batch.count) emails sent."
        if remaining > 0 { msg += " \(remaining) remaining in queue." }
        if failCount > 0 { msg += " \(failCount) failed." }
        if skippedOptOut > 0 { msg += " \(skippedOptOut) skipped (opted out)." }
        if skippedScheduled > 0 { msg += " \(skippedScheduled) skipped (scheduled)." }
        statusMessage = msg
    }

    // MARK: - Quick Draft + Auto-Approve (used by views)
    func quickDraftAndShowInOutbox(for leadID: UUID) async {
        guard let idx = leads.firstIndex(where: { $0.id == leadID }) else { return }
        if leads[idx].draftedEmail == nil { await draftEmail(for: leadID) }
        if leads[idx].draftedEmail != nil && leads[idx].draftedEmail?.isApproved == false {
            leads[idx].draftedEmail?.isApproved = true
            leads[idx].status = .emailApproved
            saveLeads()
        }
    }
}

// MARK: - PerplexityService: raw generate (for subject generation)
extension PerplexityService {
    /// Minimal single-turn generation for short prompts
    func rawGenerate(prompt: String, apiKey: String) async throws -> String {
        let system = "You are a helpful assistant. Follow instructions exactly."
        return try await callAPIPublic(systemPrompt: system, userPrompt: prompt, apiKey: apiKey, maxTokens: 300)
    }

    // Expose callAPI publicly for extensions
    func callAPIPublic(systemPrompt: String, userPrompt: String, apiKey: String, maxTokens: Int = 4000) async throws -> String {
        let requestBody = PerplexityRequest(
            model: "sonar-pro",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            max_tokens: maxTokens,
            web_search_options: .init(search_context_size: "high")
        )
        var request = URLRequest(url: URL(string: "https://api.perplexity.ai/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PplxError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PplxError.apiError(code: http.statusCode, message: String(body.prefix(300)))
        }
        let apiResp = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        guard let content = apiResp.choices?[0].message?.content else { throw PplxError.noContent }
        return content
    }
}
