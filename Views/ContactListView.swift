import SwiftUI

struct ContactListView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var filterStatus: LeadStatus?
    @State private var selectedLeads = Set<UUID>()

    var filteredLeads: [Lead] {
        var result = vm.leads
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.company.localizedCaseInsensitiveContains(searchText) ||
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Kontakte").font(.largeTitle).bold()
                Spacer()
                Text("\(filteredLeads.count) von \(vm.leads.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            // Controls
            HStack(spacing: 12) {
                TextField("Suchen...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Picker("Status", selection: $filterStatus) {
                    Text("Alle").tag(nil as LeadStatus?)
                    ForEach(LeadStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status as LeadStatus?)
                    }
                }
                .frame(width: 200)

                Spacer()

                // Batch Actions
                if !selectedLeads.isEmpty {
                    Text("\(selectedLeads.count) ausgewählt")
                        .font(.caption).foregroundStyle(.secondary)
                    
                    Button("Alle verifizieren") {
                        Task {
                            for id in selectedLeads {
                                await vm.verifyEmail(for: id)
                            }
                        }
                    }
                    .controlSize(.small)
                    
                    Button("Emails erstellen") {
                        Task {
                            for id in selectedLeads where vm.leads.first(where: { $0.id == id })?.emailVerified == true {
                                await vm.draftEmail(for: id)
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            // List
            List(selection: $selectedLeads) {
                ForEach(filteredLeads) { lead in
                    ContactRow(lead: lead, vm: vm)
                        .tag(lead.id)
                }
            }
        }
    }
}

struct ContactRow: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Info
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Titel").font(.caption).foregroundStyle(.secondary)
                        Text(lead.title).font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unternehmen").font(.caption).foregroundStyle(.secondary)
                        Text(lead.company).font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Industrie").font(.caption).foregroundStyle(.secondary)
                        Text(lead.responsibility).font(.callout)
                    }
                }

                // Email Verifikation - VERBESSERT
                GroupBox {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email").font(.caption).foregroundStyle(.secondary)
                            if lead.email.isEmpty {
                                Text("Keine Email gefunden").foregroundStyle(.red).italic()
                            } else {
                                Text(lead.email).font(.callout).bold()
                            }
                        }
                        
                        Spacer()
                        
                        if lead.emailVerified {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                Text("Verifiziert")
                                    .font(.callout).bold()
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(8)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Nicht verifiziert")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .padding(8)
                }

                // Verifikations-Notizen
                if !lead.verificationNotes.isEmpty {
                    GroupBox("Verifikations-Details") {
                        Text(lead.verificationNotes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }

                // LinkedIn
                if !lead.linkedInURL.isEmpty {
                    HStack {
                        Text("LinkedIn:").font(.caption).foregroundStyle(.secondary)
                        Link(lead.linkedInURL, destination: URL(string: lead.linkedInURL) ?? URL(string: "https://linkedin.com")!)
                            .font(.caption)
                    }
                }

                // Actions
                HStack(spacing: 8) {
                    if !lead.emailVerified {
                        Button {
                            Task { await vm.verifyEmail(for: lead.id) }
                        } label: {
                            Label("Email verifizieren", systemImage: "checkmark.shield")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    
                    if lead.emailVerified && lead.draftedEmail == nil {
                        Button {
                            Task { await vm.draftEmail(for: lead.id) }
                        } label: {
                            Label("Email erstellen", systemImage: "envelope.badge")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    
                    if lead.draftedEmail != nil {
                        Text("Email Draft vorhanden →")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Gehe zu 'Email Drafts' Tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        vm.deleteLead(lead.id)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 12) {
                // Status Circle
                Circle()
                    .fill(statusColor(lead.status))
                    .frame(width: 10, height: 10)
                
                // Name
                Text(lead.name).bold()
                
                // Company
                Text("- \(lead.company)")
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Email Verification Badge
                if lead.emailVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if !lead.email.isEmpty {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                
                // Status Badge
                Text(lead.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(lead.status).opacity(0.15))
                    .foregroundStyle(statusColor(lead.status))
                    .cornerRadius(4)
            }
        }
    }

    func statusColor(_ status: LeadStatus) -> Color {
        switch status {
        case .identified: return .gray
        case .contacted: return .orange
                    case .followedUp, .qualified: return .yellow
                    case .converted: return .green
                    case .notInterested: return .gray
                    case .emailDrafted, .emailApproved: return .blue
        case .emailSent, .followUpDrafted, .followUpSent: return .purple
        case .replied: return .green
        case .closed: return .red
        }
    }
}
