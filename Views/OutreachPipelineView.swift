import SwiftUI

// MARK: - OutreachPipelineView
// Zeigt alle Leads in einer strukturierten Pipeline-Ansicht

struct OutreachPipelineView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedLeadID: UUID?
    @State private var showEditSheet = false
    @State private var editSubject = ""
    @State private var editBody = ""
    @State private var showManualEntry = false

    var body: some View {
        HSplitView {
            // Linke Seite: Lead-Liste
            leadListSection
                .frame(minWidth: 280, idealWidth: 320)

            // Rechte Seite: Detail-Panel
            detailPanel
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView(vm: vm)
        }
    }

    // MARK: - Lead Liste
    private var leadListSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kontakte")
                        .font(.headline)
                    Text("\(vm.leads.count) Leads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showManualEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if vm.leads.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Keine Kontakte")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedLeadID) {
                    ForEach(vm.leads) { lead in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(lead.status))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(lead.name).font(.callout).bold()
                                Text(lead.company).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lead.status.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(statusColor(lead.status).opacity(0.15))
                                .cornerRadius(4)
                        }
                        .padding(.vertical, 2)
                        .tag(lead.id)
                    }
                }
            }
        }
    }

    // MARK: - Detail Panel
    private var detailPanel: some View {
        Group {
            if let leadID = selectedLeadID,
               let lead = vm.leads.first(where: { $0.id == leadID }) {
                leadDetailView(lead: lead)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Kontakt auswaehlen")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Lead Detail View
    @ViewBuilder
    private func leadDetailView(lead: Lead) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Kontakt-Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lead.name)
                                    .font(.title2).bold()
                                Text(lead.title)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text(lead.company)
                                    .font(.callout)
                            }
                            Spacer()
                            Text(lead.status.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(lead.status).opacity(0.15))
                                .cornerRadius(6)
                        }

                        Divider()

                        if !lead.email.isEmpty {
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(lead.email)
                                    .font(.caption)
                                if lead.emailVerified {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }

                        if lead.dateEmailSent != nil {
                            HStack {
                                Image(systemName: "paperplane")
                                    .foregroundStyle(.blue)
                                    .frame(width: 16)
                                Text("Email gesendet: \(lead.dateEmailSent!, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        if lead.dateFollowUpSent != nil {
                            HStack {
                                Image(systemName: "arrow.uturn.forward")
                                    .foregroundStyle(.purple)
                                    .frame(width: 16)
                                Text("Follow-Up: \(lead.dateFollowUpSent!, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
                .padding(4)

                // Email Draft Sektion
                if let draft = lead.draftedEmail {
                    emailDraftSection(lead: lead, draft: draft)
                }

                // Follow-Up Sektion
                if let followUp = lead.followUpEmail {
                    followUpSection(lead: lead, followUp: followUp)
                }

                // Aktionen
                actionButtons(lead: lead)

            }
            .padding()
        }
        .sheet(isPresented: $showEditSheet) {
            VStack(spacing: 16) {
                Text("Email bearbeiten")
                    .font(.headline)
                TextField("Betreff", text: $editSubject)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $editBody)
                    .frame(minHeight: 200)
                    .border(Color.gray.opacity(0.3))
                HStack {
                    Button("Abbrechen") { showEditSheet = false }
                    Spacer()
                    Button("Speichern") {
                        vm.updateDraft(for: lead, subject: editSubject, body: editBody)
                        showEditSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    // MARK: - Email Draft Section
    @ViewBuilder
    private func emailDraftSection(lead: Lead, draft: OutboundEmail) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    Text("Email-Entwurf")
                        .font(.headline)
                    Spacer()
                    if draft.isApproved {
                        Label("Freigegeben", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text(draft.subject)
                    .font(.callout.bold())

                Text(draft.body)
                    .font(.caption)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .lineLimit(6)

                HStack(spacing: 8) {
                    if !draft.isApproved {
                        Button("Freigeben") { vm.approveEmail(for: lead.id) }
                            .buttonStyle(.bordered)
                    }
                    Button("Bearbeiten") {
                        editSubject = draft.subject
                        editBody = draft.body
                        showEditSheet = true
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if draft.isApproved && lead.dateEmailSent == nil {
                        Button("Senden") { Task { await vm.sendEmail(for: lead.id) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(4)
    }

    // MARK: - Follow-Up Section
    @ViewBuilder
    private func followUpSection(lead: Lead, followUp: OutboundEmail) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundStyle(.purple)
                    Text("Follow-Up")
                        .font(.headline)
                    Spacer()
                    if lead.dateFollowUpSent != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Follow-Up gesendet")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Text(followUp.subject).font(.callout.bold())

                Text(followUp.body)
                    .font(.caption)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .lineLimit(6)

                if lead.dateFollowUpSent == nil {
                    HStack(spacing: 8) {
                        if !followUp.isApproved {
                            Button("Freigeben") { vm.approveFollowUp(for: lead.id) }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button("Senden") { Task { await vm.sendFollowUp(for: lead.id) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!followUp.isApproved)
                    }
                }
            }
        }
        .padding(4)
    }

    // MARK: - Action Buttons
    @ViewBuilder
    private func actionButtons(lead: Lead) -> some View {
        HStack(spacing: 8) {
            if lead.draftedEmail == nil {
                Button("Email erstellen") {
                    Task { await vm.draftEmail(for: lead.id) }
                }
                .buttonStyle(.bordered)
            }
            if lead.draftedEmail != nil && lead.followUpEmail == nil && lead.dateEmailSent != nil {
                Button("Follow-Up erstellen") {
                    Task { await vm.draftFollowUpFromContact(for: lead.id) }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(role: .destructive) {
                vm.deleteLead(lead.id)
                selectedLeadID = nil
            } label: {
                Label("Loeschen", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Hilfs-Funktion: Status-Farbe
    private func statusColor(_ status: LeadStatus) -> Color {
        switch status {
        case .identified: return .gray
        case .contacted: return .orange
        case .emailDrafted, .emailApproved: return .blue
        case .emailSent: return .blue
        case .followUpDrafted, .followUpSent: return .purple
        case .replied: return .green
        case .followedUp, .qualified, .converted: return .green
        case .notInterested, .doNotContact, .closed: return .red
        }
    }
}
