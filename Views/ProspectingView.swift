import SwiftUI

struct ProspectingView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showManualCompanySheet = false
    @State private var showManualContactSheet = false
    @State private var selectedCompanyForContact: Company?
    
    var body: some View {
        VStack(spacing: 0) {
            ProspectingHeaderView(vm: vm)
            Divider()
            HStack(spacing: 0) {
                ProspectingCompanyList(vm: vm, showManualCompanySheet: $showManualCompanySheet, showManualContactSheet: $showManualContactSheet, selectedCompanyForContact: $selectedCompanyForContact)
                Divider()
                ProspectingContactList(vm: vm)
            }
        }
        .sheet(isPresented: $showManualCompanySheet) {
            ManualCompanyEntryView(vm: vm)
        }
        .sheet(isPresented: $showManualContactSheet) {
            if let company = selectedCompanyForContact {
                ManualContactEntryView(vm: vm, company: company)
            }
        }
    }
}

// MARK: - Header
struct ProspectingHeaderView: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Prospecting").font(.largeTitle).bold()
                Text("Unternehmen und Kontakte finden").foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isLoading {
                ProgressView()
                Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

// MARK: - Company List (Left)
struct ProspectingCompanyList: View {
    @ObservedObject var vm: AppViewModel
    @Binding var showManualCompanySheet: Bool
    @Binding var showManualContactSheet: Bool
    @Binding var selectedCompanyForContact: Company?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unternehmen").font(.headline)
                Spacer()
                Menu {
                    Button(action: { Task { await vm.findCompanies() } }) {
                        Label("Automatische Suche", systemImage: "magnifyingglass")
                    }
                    Button(action: { showManualCompanySheet = true }) {
                        Label("Unternehmen manuell hinzufuegen", systemImage: "plus.circle")
                    }
                } label: {
                    Label("Unternehmen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading)
            }
            if vm.isLoading {
                Button("Abbrechen", role: .cancel) { vm.cancelOperation() }.buttonStyle(.bordered)
            }
            if !vm.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(vm.errorMessage).font(.caption).foregroundStyle(.red)
                }.padding(8).background(Color.red.opacity(0.1)).cornerRadius(8)
            }
            if vm.companies.isEmpty {
                VStack { Spacer(); Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(.secondary); Text("Noch keine Unternehmen").font(.headline).foregroundStyle(.secondary); Spacer() }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(vm.companies) { company in
                        CompanyRow(company: company, onFindContacts: { Task { await vm.findContacts(for: company) } }, onAddManual: { selectedCompanyForContact = company; showManualContactSheet = true })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}

// MARK: - Contact List (Right)
struct ProspectingContactList: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gefundene Kontakte").font(.headline)
                Spacer()
                Text("\(vm.leads.count) Kontakte").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Alle Kontakte suchen") { Task { await vm.findContactsForAll() } }.disabled(vm.companies.isEmpty || vm.isLoading)
                Button("Alle Emails verifizieren") { Task { await vm.verifyAllEmails() } }.disabled(vm.leads.isEmpty || vm.isLoading).buttonStyle(.borderedProminent).tint(.orange)
            }
            if vm.leads.isEmpty {
                VStack { Spacer(); Image(systemName: "person.2").font(.system(size: 48)).foregroundStyle(.secondary); Text("Keine Kontakte").font(.headline).foregroundStyle(.secondary); Spacer() }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(vm.leads) { lead in
                        LeadRowProspecting(lead: lead, onVerify: { Task { await vm.verifyEmail(for: lead.id) } })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}

// MARK: - Company Row
struct CompanyRow: View {
    let company: Company
    let onFindContacts: () -> Void
    let onAddManual: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name).font(.headline)
                HStack(spacing: 8) {
                    Text(company.industry).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.blue.opacity(0.1)).cornerRadius(4)
                    Text(company.region).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.green.opacity(0.1)).cornerRadius(4)
                }
                if !company.website.isEmpty { Text(company.website).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                Button(action: onFindContacts) { Label("Kontakte automatisch suchen", systemImage: "magnifyingglass") }
                Button(action: onAddManual) { Label("Kontakt manuell hinzufuegen", systemImage: "plus") }
            } label: { Text("Aktionen").font(.caption) }
            .controlSize(.small)
        }.padding(.vertical, 4)
    }
}

// MARK: - Lead Row
struct LeadRowProspecting: View {
    let lead: Lead
    let onVerify: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name).font(.headline)
                Text(lead.title).font(.subheadline).foregroundStyle(.secondary)
                Text(lead.company).font(.caption)
                if !lead.email.isEmpty {
                    HStack(spacing: 6) {
                        Text(lead.email).font(.caption).bold()
                        if lead.emailVerified || lead.isManuallyCreated {
                            HStack(spacing: 2) {
                                Image(systemName: lead.isManuallyCreated ? "person.badge.checkmark" : "checkmark.seal.fill").foregroundStyle(.green)
                                Text(lead.isManuallyCreated ? "Manuell" : "Verifiziert").font(.caption2).bold().foregroundStyle(.green)
                            }.padding(.horizontal, 6).padding(.vertical, 2).background(Color.green.opacity(0.15)).cornerRadius(4)
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text("Nicht verifiziert").font(.caption2).foregroundStyle(.orange)
                            }.padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.15)).cornerRadius(4)
                        }
                    }
                } else {
                    Text("Keine Email gefunden").font(.caption).foregroundStyle(.red).italic()
                }
            }
            Spacer()
            if !lead.emailVerified && !lead.isManuallyCreated && !lead.email.isEmpty {
                Button("Verifizieren") { onVerify() }.controlSize(.small).buttonStyle(.borderedProminent).tint(.orange)
            } else if lead.emailVerified || lead.isManuallyCreated {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            }
        }.padding(.vertical, 4)
    }
}

// MARK: - Manual Company Entry (FESTE GROESSE)
struct ManualCompanyEntryView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var companyName = ""
    @State private var industry = Industry.healthcare
    @State private var region = Region.dach
    @State private var website = ""
    @State private var companyDescription = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header mit Buttons
            HStack {
                Text("Unternehmen hinzufuegen").font(.title2).bold()
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.escape).buttonStyle(.bordered)
                Button("Hinzufuegen") {
                    let company = Company(name: companyName, industry: industry.rawValue, region: region.rawValue, website: website, description: companyDescription)
                    vm.addCompanyManually(company)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(companyName.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding(24)
            
            Divider()
            
            // Formular
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Firmenname *").font(.headline)
                        TextField("z.B. Siemens AG", text: $companyName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Branche *").font(.headline)
                            Picker("Branche", selection: $industry) {
                                ForEach(Industry.allCases) { ind in Text(ind.rawValue).tag(ind) }
                            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Region *").font(.headline)
                            Picker("Region", selection: $region) {
                                ForEach(Region.allCases) { reg in Text(reg.rawValue).tag(reg) }
                            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Website").font(.headline)
                        TextField("https://www.example.com", text: $website)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Beschreibung").font(.headline)
                        TextEditor(text: $companyDescription)
                            .frame(minHeight: 80)
                            .font(.body)
                            .border(Color.gray.opacity(0.3))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 700, height: 550)
    }
}

// MARK: - Manual Contact Entry (FESTE GROESSE + emailVerified + isManuallyCreated)
struct ManualContactEntryView: View {
    @ObservedObject var vm: AppViewModel
    let company: Company
    @Environment(\.dismiss) var dismiss
    @State private var contactName = ""
    @State private var title = ""
    @State private var email = ""
    @State private var linkedIn = ""
    @State private var responsibility = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kontakt hinzufuegen").font(.title2).bold()
                    Text("Unternehmen: \(company.name)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.escape).buttonStyle(.bordered)
                Button("Hinzufuegen") {
                    let lead = Lead(
                        name: contactName,
                        title: title,
                        company: company.name,
                        email: email,
                        emailVerified: true,
                        linkedInURL: linkedIn,
                        responsibility: responsibility,
                        status: .identified,
                        source: "Manueller Eintrag",
                        isManuallyCreated: true
                    )
                    vm.addLeadManually(lead)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(contactName.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding(24)
            
            Divider()
            
            // Formular - keine GroupBox, direkte VStacks
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name *").font(.headline)
                        TextField("Vor- und Nachname", text: $contactName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    // Position
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Position / Titel").font(.headline)
                        TextField("z.B. Chief Compliance Officer", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    // Email
                    VStack(alignment: .leading, spacing: 6) {
                        Text("E-Mail").font(.headline)
                        TextField("name@unternehmen.de", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            Text("Manuelle Kontakte brauchen keine Email-Verifikation")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                    
                    Divider()
                    
                    // LinkedIn
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LinkedIn URL (optional)").font(.headline)
                        TextField("https://linkedin.com/in/...", text: $linkedIn)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    // Verantwortungsbereich
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verantwortungsbereich (optional)").font(.headline)
                        TextEditor(text: $responsibility)
                            .frame(minHeight: 60)
                            .font(.body)
                            .border(Color.gray.opacity(0.3))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 800, height: 750)
    }
}
