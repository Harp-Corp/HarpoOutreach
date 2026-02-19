import SwiftUI

struct EmailDraftView: View {
    @ObservedObject var vm: AppViewModel

    // Leads ohne Draft
    var draftsNeeded: [Lead] {
        vm.leads.filter { ($0.emailVerified || $0.isManuallyCreated) && $0.draftedEmail == nil }
    }

    // Leads mit Draft, noch nicht gesendet
    var draftsReady: [Lead] {
                vm.leads.filter { $0.draftedEmail != nil && $0.draftedEmail?.sentDate == nil }
    }

    // NEU: Follow-Up Drafts (erstellt aber noch nicht gesendet)
    var followUpDraftsReady: [Lead] {
        vm.leads.filter { $0.followUpEmail != nil && $0.followUpEmail?.sentDate == nil }
    }

    @State private var selectedLead: Lead?
    @State private var showingEditSheet = false
    @State private var showingSendConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var editSubject = ""
    @State private var emailBody = ""
    // NEU: State fuer Follow-Up Edit
    @State private var showingFollowUpEditSheet = false
    @State private var showingFollowUpSendConfirmation = false
    @State private var showingFollowUpDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            EmailDraftHeaderView(vm: vm, draftsNeeded: draftsNeeded)

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text("\(vm.currentStep)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Divider()

            // FIX: Fehlermeldung auf Email Drafts Screen anzeigen
            if !vm.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(vm.errorMessage).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("X") { vm.errorMessage = "" }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            if draftsReady.isEmpty && draftsNeeded.isEmpty && followUpDraftsReady.isEmpty {
                EmailDraftEmptyView()
            } else {
                List {
                    if !draftsNeeded.isEmpty {
                        Section("Email noch zu erstellen (\(draftsNeeded.count))") {
                            ForEach(draftsNeeded, id: \.id) { lead in
                                EmailDraftNeededRow(lead: lead, vm: vm)
                            }
                        }
                    }

                    if !draftsReady.isEmpty {
                        Section("Fertige Drafts (\(draftsReady.count))") {
                            ForEach(draftsReady, id: \.id) { lead in
                                EmailDraftReadyRow(
                                    lead: lead,
                                    onEdit: {
                                        selectedLead = lead
                                        if let draft = lead.draftedEmail {
                                            editSubject = draft.subject
                                            emailBody = draft.body
                                        }
                                        showingEditSheet = true
                                    },
                                    onSend: {
                                        selectedLead = lead
                                        showingSendConfirmation = true
                                    },
                                    onDelete: {
                                        selectedLead = lead
                                        showingDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }

                    // NEU: Follow-Up Drafts
                    if !followUpDraftsReady.isEmpty {
                        Section("Follow-Up Drafts (\(followUpDraftsReady.count))") {
                            ForEach(followUpDraftsReady, id: \.id) { lead in
                                FollowUpDraftReadyRow(
                                    lead: lead,
                                    onEdit: {
                                        selectedLead = lead
                                        if let fu = lead.followUpEmail {
                                            editSubject = fu.subject
                                            emailBody = fu.body
                                        }
                                        showingFollowUpEditSheet = true
                                    },
                                    onSend: {
                                        selectedLead = lead
                                        showingFollowUpSendConfirmation = true
                                    },
                                    onDelete: {
                                        selectedLead = lead
                                        showingFollowUpDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        // MARK: - Original Email Sheet + Alerts
        .sheet(isPresented: $showingEditSheet) {
            if let lead = selectedLead {
                EditDraftSheet(
                    lead: lead,
                    subject: $editSubject,
                    emailBody: $emailBody,
                    onSave: { newSubject, newBody in
                        vm.updateDraft(for: lead, subject: newSubject, body: newBody)
                        showingEditSheet = false
                    },
                    onCancel: { showingEditSheet = false }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        .alert("Email senden?", isPresented: $showingSendConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") {
                if let lead = selectedLead {
                    Task { await vm.sendEmail(to: lead) }
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll die Email an \(lead.name) (\(lead.email)) gesendet werden?")
            }
        }
        .alert("Draft loeschen?", isPresented: $showingDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loeschen", role: .destructive) {
                if let lead = selectedLead { vm.deleteDraft(for: lead) }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll der Email-Draft fuer \(lead.name) geloescht werden?")
            }
        }
        // MARK: - Follow-Up Sheet + Alerts
        .sheet(isPresented: $showingFollowUpEditSheet) {
            if let lead = selectedLead {
                EditDraftSheet(
                    lead: lead,
                    subject: $editSubject,
                    emailBody: $emailBody,
                    titleLabel: "Follow-Up bearbeiten",
                    onSave: { newSubject, newBody in
                        vm.updateFollowUpDraft(for: lead, subject: newSubject, body: newBody)
                        showingFollowUpEditSheet = false
                    },
                    onCancel: { showingFollowUpEditSheet = false }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        .alert("Follow-Up senden?", isPresented: $showingFollowUpSendConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") {
                if let lead = selectedLead {
                    // Erst freigeben, dann senden
                    vm.approveFollowUp(for: lead.id)
                    Task { await vm.sendFollowUp(for: lead.id) }
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll das Follow-Up an \(lead.name) (\(lead.email)) gesendet werden?")
            }
        }
        .alert("Follow-Up Draft loeschen?", isPresented: $showingFollowUpDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loeschen", role: .destructive) {
                if let lead = selectedLead { vm.deleteFollowUpDraft(for: lead) }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll der Follow-Up Draft fuer \(lead.name) geloescht werden?")
            }
        }
    }
}

// MARK: - Header
struct EmailDraftHeaderView: View {
    @ObservedObject var vm: AppViewModel
    let draftsNeeded: [Lead]

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Email Drafts")
                    .font(.largeTitle).bold()
                Text("Emails bearbeiten, loeschen oder versenden")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Alle Emails generieren") {
                Task { await vm.draftAllEmails() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftsNeeded.isEmpty || vm.isLoading)
        }
        .padding(24)
    }
}

// MARK: - Empty State
struct EmailDraftEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "envelope.badge")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Keine Drafts vorhanden.")
                .foregroundStyle(.secondary)
            Text("Verifiziere zuerst Emails im Prospecting-Tab.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

// MARK: - Draft Needed Row
struct EmailDraftNeededRow: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel

    var body: some View {
        HStack {
            Text(lead.name).bold()
            Text(lead.company).font(.caption)
            Spacer()
            Button("Draft erstellen") {
                Task { await vm.draftEmail(for: lead.id) }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
        }
    }
}

// MARK: - Draft Ready Row
struct EmailDraftReadyRow: View {
    let lead: Lead
    let onEdit: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmailDraftReadyHeader(lead: lead)
            EmailDraftPreview(draft: lead.draftedEmail)
            EmailDraftActions(onEdit: onEdit, onSend: onSend, onDelete: onDelete)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - NEU: Follow-Up Draft Ready Row
struct FollowUpDraftReadyRow: View {
    let lead: Lead
    let onEdit: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.forward")
                            .foregroundStyle(.purple)
                        Text(lead.name).bold()
                    }
                    Text(lead.company).font(.caption).foregroundStyle(.secondary)
                    Text(lead.email).font(.caption).foregroundStyle(.blue)
                }
                Spacer()
                Text("Follow-Up")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.2))
                    .foregroundColor(.purple)
                    .clipShape(Capsule())
            }
            // Follow-Up Draft Preview
            if let followUp = lead.followUpEmail {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Betreff: \(followUp.subject)")
                            .font(.subheadline).bold()
                        Text(followUp.body)
                            .font(.caption)
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            EmailDraftActions(onEdit: onEdit, onSend: onSend, onDelete: onDelete)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Draft Ready Header
struct EmailDraftReadyHeader: View {
    let lead: Lead

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(lead.name).bold()
                Text(lead.company).font(.caption).foregroundStyle(.secondary)
                Text(lead.email).font(.caption).foregroundStyle(.blue)
            }
            Spacer()
            if lead.isManuallyCreated {
                Text("Manuell")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Draft Preview
struct EmailDraftPreview: View {
    let draft: OutboundEmail?

    var body: some View {
        if let draft = draft {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Betreff: \(draft.subject)")
                        .font(.subheadline).bold()
                    Text(draft.body)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Draft Actions
struct EmailDraftActions: View {
    let onEdit: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onEdit()
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .buttonStyle(.bordered)

            Button {
                onSend()
            } label: {
                Label("Senden", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Loeschen", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Edit Draft Sheet (wiederverwendbar fuer Email + Follow-Up)
struct EditDraftSheet: View {
    let lead: Lead
    @Binding var subject: String
    @Binding var emailBody: String
    var titleLabel: String = "Email bearbeiten"
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(titleLabel)
                        .font(.headline)
                    Text("An: \(lead.name) <\(lead.email)>")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { onCancel() }
                    .buttonStyle(.bordered)
                Button("Speichern") { onSave(subject, emailBody) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Section("Betreff") {
                    TextField("Betreff", text: $subject)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Nachricht") {
                    TextEditor(text: $emailBody)
                        .frame(minHeight: 250)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    EmailDraftView(vm: AppViewModel())
}
