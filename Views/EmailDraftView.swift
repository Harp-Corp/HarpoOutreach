import SwiftUI

struct EmailDraftView: View {
    @ObservedObject var vm: AppViewModel

    var draftsNeeded: [Lead] {
        vm.leads.filter { $0.emailVerified && $0.draftedEmail == nil }
    }

    var draftsReady: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Email Drafts").font(.largeTitle).bold()
                    Text("Personalisierte Emails erstellen und freigeben")
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

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Divider()

            if draftsReady.isEmpty && draftsNeeded.isEmpty {
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
            } else {
                List {
                    if !draftsNeeded.isEmpty {
                        Section("Email noch zu erstellen (\(draftsNeeded.count))") {
                            ForEach(draftsNeeded) { lead in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(lead.name).bold()
                                        Text(lead.company.name).font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Email erstellen") {
                                        Task { await vm.draftEmail(for: lead.id) }
                                    }
                                    .controlSize(.small)
                                    .disabled(vm.isLoading)
                                }
                            }
                        }
                    }

                    if !draftsReady.isEmpty {
                        Section("Erstellte Drafts (\(draftsReady.count))") {
                            ForEach(draftsReady) { lead in
                                DraftCard(lead: lead, vm: vm)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DraftCard: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel
    @State private var editSubject: String = ""
    @State private var editBody: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(lead.name).font(.headline)
                    Text("\(lead.title) - \(lead.company.name)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("An: \(lead.email)").font(.caption)
                }
                Spacer()
                if lead.draftedEmail?.isApproved == true {
                    Label("Freigegeben", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                }
            }

            Divider()

            if isEditing {
                TextField("Betreff", text: $editSubject)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $editBody)
                    .frame(minHeight: 150)
                    .border(Color.gray.opacity(0.3))
                HStack {
                    Button("Speichern") {
                        var updated = lead
                        updated.draftedEmail?.subject = editSubject
                        updated.draftedEmail?.body = editBody
                        vm.updateLead(updated)
                        isEditing = false
                    }
                    Button("Abbrechen", role: .cancel) {
                        isEditing = false
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Betreff:").font(.caption).foregroundStyle(.secondary)
                    Text(lead.draftedEmail?.subject ?? "")
                        .font(.headline)
                    Text("Email:").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(lead.draftedEmail?.body ?? "")
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }

                HStack(spacing: 8) {
                    Button("Bearbeiten") {
                        editSubject = lead.draftedEmail?.subject ?? ""
                        editBody = lead.draftedEmail?.body ?? ""
                        isEditing = true
                    }
                    .controlSize(.small)

                    if lead.draftedEmail?.isApproved != true {
                        Button("Freigeben") {
                            vm.approveEmail(for: lead.id)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}
