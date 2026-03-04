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
        let regionContext = company?.region ?? "DACH"
        let sizeContext = company.map { $0.employeeCount > 0 ? "\($0.employeeCount) Mitarbeiter" : $0.size } ?? ""
        let companyDescription = company?.description ?? ""

        // Finde relevante Regulierungen basierend auf Branche
        let regulations = Industry.allCases
            .first { $0.rawValue == industryContext || industryContext.contains($0.naceSection) }
            .map { $0.keyRegulations } ?? "NIS2, DSGVO, DORA"

        let prompt = """
        Erstelle ein professionelles, personalisiertes Outreach-Email auf Englisch fuer:

        Empfaenger: \(lead.name)
        Position: \(lead.title.isEmpty ? "Decision Maker" : lead.title)
        Unternehmen: \(lead.company)
        Branche: \(industryContext)
        Region: \(regionContext)
        Unternehmensgroesse: \(sizeContext)
        Unternehmensbeschreibung: \(companyDescription)

        Relevante Regulierungen: \(regulations)

        Absender: Martin Foerster, Harpocrates Corp
        Produkt: comply.reg - Automated Regulatory Monitoring Platform
        - Trackt regulatorische Aenderungen automatisch
        - Mappt Obligations auf Unternehmensoperationen
        - Flaggt Deadline-Drift und orchestriert Evidence Collection
        - Deckt NIS2, DORA, DSGVO, EU AI Act, CSRD und weitere ab

        Anforderungen:
        1. Betreff: Kurz, relevant, personalisiert (max 60 Zeichen)
        2. Anrede mit Vorname
        3. Beziehe dich auf aktuelle regulatorische Herausforderungen der Branche
        4. Erklaere konkret wie comply.reg bei \(lead.company) helfen kann
        5. Klarer Call-to-Action (kurzes Gespraech/Demo)
        6. Professionell aber nicht zu formell
        7. Max 200 Woerter Body
        8. KEIN Opt-Out Text (wird automatisch angefuegt)

        Format: Erste Zeile = Subject, dann Leerzeile, dann Body.
        """

        let result = try await pplxService.generateText(prompt: prompt, apiKey: settings.perplexityAPIKey)

        // Parse: Erste Zeile = Subject, Rest = Body
        let lines = result.components(separatedBy: "\n")
        var subject = ""
        var body = ""

        if let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            subject = firstNonEmpty
                .replacingOccurrences(of: "Subject: ", with: "")
                .replacingOccurrences(of: "Betreff: ", with: "")
                .trimmingCharacters(in: .whitespaces)

            if let idx = lines.firstIndex(where: { $0 == firstNonEmpty }) {
                body = lines.dropFirst(idx + 1)
                    .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Opt-Out Footer automatisch anfuegen
        let optOutFooter = "\n\n---\nIf you no longer wish to receive emails from us, please reply with 'unsubscribe' or click here: https://comply.reg/optout?email=\(lead.email)"
        body += optOutFooter

        return OutboundEmail(subject: subject, body: body)
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
                    to: leads[idx].email,
                    subject: approvedEmail.subject,
                    body: approvedEmail.body,
                    from: senderEmail
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
