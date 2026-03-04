import Foundation
import SwiftUI

// MARK: - AppViewModel+OutboundSingle
// Feature 4: Personalisiertes Outbound an einzelne Ansprechpartner
// - Generierung von persoenlichem Anschreiben unter Beruecksichtigung von
//   Unternehmenssituation, Position, Compliance-Status, Harpocrates Produktoffering
// - Draft speichern, Review, Freigabe und Versand

extension AppViewModel {

    // MARK: - Generate Personal Outbound Email
    /// Generiert ein personalisiertes Anschreiben fuer einen einzelnen Kontakt
    /// Beruecksichtigt: Unternehmenssituation, Position, Compliance-Status der Branche, Harpocrates Offering
    func generatePersonalOutbound(for lead: Lead) async throws -> OutboundEmail {
        guard !settings.perplexityAPIKey.isEmpty else {
            throw OutboundError.missingAPIKey
        }

        // Finde das zugehoerige Unternehmen fuer mehr Kontext
        let company = companies.first { $0.name.lowercased() == lead.company.lowercased() }

        let industryContext = company?.industry ?? "unbekannte Branche"

        // Recherchiere Branchen-Challenges fuer Personalisierung
        var challenges = ""
        if let company = company {
            do {
                challenges = try await pplxService.researchChallenges(company: company, apiKey: settings.perplexityAPIKey)
            } catch {
                challenges = "General regulatory compliance challenges in \(industryContext)"
            }
        } else {
            challenges = "General regulatory compliance challenges in \(industryContext)"
        }

                // Verwende draftEmail aus PerplexityService
        let senderName = "Martin Foerster"

        var email = try await pplxService.draftEmail(
            lead: lead,
            challenges: challenges,
            senderName: senderName,
            apiKey: settings.perplexityAPIKey
        )

        // Opt-Out Footer automatisch anfuegen
        let optOutFooter = "\n\n---\nIf you no longer wish to receive emails from us, please reply with 'unsubscribe' or click here: https://comply.reg/optout?email=\(lead.email)"
        email = OutboundEmail(subject: email.subject, body: email.body + optOutFooter)

        return email
    }

    // MARK: - Save Draft for Lead
    func saveDraftForLead(leadId: UUID, email: OutboundEmail) {
        if let idx = leads.firstIndex(where: { $0.id == leadId }) {
            leads[idx].draftedEmail = email
            leads[idx].status = .emailDrafted
            DatabaseService.shared.saveLead(leads[idx])

            // Log outreach action
            DatabaseService.shared.logOutreach(
                leadId: leadId,
                action: "draft_saved",
                subject: email.subject,
                channel: "email"
            )
        }
    }

    // MARK: - Approve and Send Single
    func approveAndSendSingle(leadId: UUID, email: OutboundEmail) {
        guard let idx = leads.firstIndex(where: { $0.id == leadId }) else { return }

        var approvedEmail = email
        approvedEmail.isApproved = true
        leads[idx].draftedEmail = approvedEmail
        leads[idx].status = .emailApproved
        DatabaseService.shared.saveLead(leads[idx])

        // Send via Gmail
        Task {
            do {
                try await gmailService.sendEmail(
                    from: senderEmail,
                    to: leads[idx].email,
                    subject: approvedEmail.subject,
                    body: approvedEmail.body
                )

                await MainActor.run {
                    if let i = self.leads.firstIndex(where: { $0.id == leadId }) {
                        self.leads[i].status = .emailSent
                        self.leads[i].dateEmailSent = Date()
                        self.leads[i].deliveryStatus = .sent
                        self.leads[i].draftedEmail?.sentDate = Date()
                        DatabaseService.shared.saveLead(self.leads[i])
                        DatabaseService.shared.logOutreach(
                            leadId: leadId,
                            action: "email_sent",
                            subject: approvedEmail.subject,
                            channel: "email"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Senden fehlgeschlagen: \(error.localizedDescription)"
                    if let i = self.leads.firstIndex(where: { $0.id == leadId }) {
                        self.leads[i].deliveryStatus = .failed
                        DatabaseService.shared.saveLead(self.leads[i])
                    }
                }
            }
        }
    }

    // MARK: - Delete Helpers (used by AddressBookView)
    func deleteCompany(_ company: Company) {
        companies.removeAll { $0.id == company.id }
        DatabaseService.shared.deleteCompany(company.id)
    }

    func deleteLead(_ lead: Lead) {
        leads.removeAll { $0.id == lead.id }
        DatabaseService.shared.deleteLead(lead.id)
    }
}

// MARK: - Outbound Errors
enum OutboundError: LocalizedError {
    case missingAPIKey
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Perplexity API Key fehlt. Bitte in Einstellungen konfigurieren."
        case .generationFailed(let msg):
            return "Generierung fehlgeschlagen: \(msg)"
        }
    }
}
