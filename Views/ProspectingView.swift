import SwiftUI

struct ProspectingView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Prospecting")
                        .font(.largeTitle).bold()
                    Text("Unternehmen und Kontakte finden")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isLoading {
                    ProgressView()
                    Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Unternehmen").font(.headline)
                        Spacer()
                        Button("Unternehmen suchen") {
                            Task { await vm.findCompanies() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isLoading)
                    }

                    if vm.companies.isEmpty {
                        VStack {
                            Spacer()
                            Text("Noch keine Unternehmen gesucht.")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(vm.companies) { company in
                                CompanyRow(company: company) {
                                    Task { await vm.findContacts(for: company) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Gefundene Kontakte").font(.headline)
                        Spacer()
                        Text("\(vm.leads.count) Kontakte")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Alle Kontakte suchen") {
                            Task { await vm.findContactsForAll() }
                        }
                        .disabled(vm.companies.isEmpty || vm.isLoading)

                        Button("Alle Emails verifizieren") {
                            Task { await vm.verifyAllEmails() }
                        }
                        .disabled(vm.leads.isEmpty || vm.isLoading)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    if vm.leads.isEmpty {
                        VStack {
                            Spacer()
                            Text("Wähle ein Unternehmen und suche Kontakte.")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(vm.leads) { lead in
                                LeadRowProspecting(lead: lead, onVerify: {
                                    Task { await vm.verifyEmail(for: lead.id) }
                                })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
    }
}

struct CompanyRow: View {
    let company: Company
    let onFindContacts: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.headline)
                HStack(spacing: 8) {
                    Text(company.industry).font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.1)).cornerRadius(4)
                    Text(company.region).font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.1)).cornerRadius(4)
                }
                if !company.website.isEmpty {
                    Text(company.website).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Kontakte suchen") { onFindContacts() }
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

struct LeadRowProspecting: View {
    let lead: Lead
    let onVerify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name).font(.headline)
                Text(lead.title).font(.subheadline).foregroundStyle(.secondary)
                Text(lead.company.name).font(.caption)
                
                if !lead.email.isEmpty {
                    HStack(spacing: 6) {
                        Text(lead.email).font(.caption).bold()
                        if lead.emailVerified {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Verifiziert")
                                    .font(.caption2).bold()
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Nicht verifiziert")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                } else {
                    Text("Keine Email gefunden")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .italic()
                }
            }
            Spacer()
            if !lead.emailVerified && !lead.email.isEmpty {
                Button("Verifizieren") { onVerify() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            } else if lead.emailVerified {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

