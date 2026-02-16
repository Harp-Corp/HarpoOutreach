import SwiftUI

struct ProspectingView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showManualCompanySheet = false
    @State private var showManualContactSheet = false
    @State private var selectedCompanyForContact: Company?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                // Left: Companies
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Unternehmen").font(.headline)
                        Spacer()
                        Menu {
                            Button(action: { Task { await vm.findCompanies() } }) {
                                Label("Automatische Suche", systemImage: "magnifyingglass")
                            }
                            Button(action: { showManualCompanySheet = true }) {
                                Label("Unternehmen manuell hinzufügen", systemImage: "plus.circle")
                            }
                        } label: {
                            Label("Unternehmen", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isLoading)
                    }
                    
                    // Cancel button during loading
                    if vm.isLoading {
                        Button("Abbrechen", role: .cancel) {
                            vm.cancelOperation()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Error message
                    if !vm.errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(vm.errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if vm.companies.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "building.2")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Noch keine Unternehmen")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Starte eine automatische Suche oder füge manuell hinzu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(vm.companies) { company in
                                CompanyRow(company: company, onFindContacts: {
                                    Task { await vm.findContacts(for: company) }
                                }, onAddManual: {
                                    selectedCompanyForContact = company
                                    showManualContactSheet = true
                                })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                
                Divider()
                
                // Right: Contacts
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
                            Image(systemName: "person.2")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Keine Kontakte")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Wähle ein Unternehmen und suche Kontakte")
                                .font(.caption)
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
        .sheet(isPresented: $showManualCompanySheet) {
            ManualCompanyEntryView(vm: vm)
                            .frame(minWidth: 600, minHeight: 500)
        }
                
        .sheet(isPresented: $showManualContactSheet) {
            if let company = selectedCompanyForContact {
                ManualContactEntryView(vm: vm, company: company)
                                .frame(minWidth: 600, minHeight: 500)
                    
        }
    }
}

struct CompanyRow: View {
    let company: Company
    let onFindContacts: () -> Void
    let onAddManual: () -> Void
    
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
            Menu {
                Button(action: onFindContacts) {
                    Label("Kontakte automatisch suchen", systemImage: "magnifyingglass")
                }
                Button(action: onAddManual) {
                    Label("Kontakt manuell hinzufügen", systemImage: "plus")
                }
            } label: {
                Text("Aktionen")
                    .font(.caption)
            }
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

// MARK: - Manual Company Entry
struct ManualCompanyEntryView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var companyName = ""
    @State private var industry = Industry.healthcare
    @State private var region = Region.dach
    @State private var website = ""
    @State private var description = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Unternehmensdetails") {
                    TextField("Firmenname", text: $companyName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    Picker("Branche", selection: $industry) {
                        ForEach(Industry.allCases) { ind in
                            Text(ind.rawValue).tag(ind)
                        }
                    }
                    Picker("Region", selection: $region) {
                        ForEach(Region.allCases) { reg in
                            Text(reg.rawValue).tag(reg)
                        }
                    }
                    TextField("Website (optional)", text: $website)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    TextField("Beschreibung (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                            .formStyle(.grouped)
            }
            .navigationTitle("Unternehmen hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let company = Company(
                            name: companyName,
                            industry: industry.rawValue,
                            region: region.rawValue,
                            website: website,
                            description: description,
                            source: "manual"
                        )
                        vm.addCompanyManually(company)
                        dismiss()
                    }
                    .disabled(companyName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Manual Contact Entry
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
        NavigationView {
            Form {
                Section("Unternehmen") {
                    Text(company.name)
                        .font(.headline)
                }
                
                Section("Kontaktdetails") {
                    TextField("Name", text: $contactName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    TextField("Position/Titel", text: $title)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    TextField("Email", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    TextField("LinkedIn URL (optional)", text: $linkedIn)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                    TextField("Verantwortungsbereich (optional)", text: $responsibility)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                }
            }
                        .formStyle(.grouped)
            .navigationTitle("Kontakt hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let lead = Lead(
                            name: contactName,
                            title: title,
                            company: company,
                            email: email,
                            linkedInURL: linkedIn,
                            responsibility: responsibility,
                            status: .identified,
                            source: "manual"
                        )
                        vm.addLeadManually(lead)
                        dismiss()
                    }
                    .disabled(contactName.isEmpty || title.isEmpty)
                }
            }
        }
    }
        }
}
