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
        .sheet(item: $selectedCompanyForContact) { company in
            ManualContactEntryView(vm: vm, company: company)
        }
    }
}

// MARK: - Header with Industry Filter + CompanySize Filter
struct ProspectingHeaderView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Prospecting").font(.largeTitle).bold()
                    Text("Find companies and contacts").foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isLoading { ProgressView(); Text(vm.currentStep).font(.caption).foregroundStyle(.secondary) }
            }

            // Industry filter tabs
            HStack(spacing: 8) {
                Button(action: { vm.selectedIndustryFilter = nil }) {
                    Text("All Industries")
                }
                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                .background(vm.selectedIndustryFilter == nil ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(vm.selectedIndustryFilter == nil ? .white : .primary)
                .cornerRadius(8)
                .buttonStyle(.plain)

                ForEach(Industry.allCases) { industry in
                    Button(action: { vm.selectedIndustryFilter = industry }) {
                        HStack(spacing: 4) {
                            Image(systemName: industry.icon).font(.caption2)
                            Text(industry.shortName).font(.caption)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(vm.selectedIndustryFilter == industry ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundColor(vm.selectedIndustryFilter == industry ? .white : .primary)
                    .cornerRadius(8)
                    .buttonStyle(.plain)
                }
            }

            // NEW: CompanySize filter chips
            HStack(spacing: 8) {
                Text("Groesse:").font(.caption).foregroundStyle(.secondary)
                ForEach(CompanySize.allCases) { size in
                    let isSelected = vm.settings.selectedCompanySizes.contains(size.rawValue)
                    Button(action: {
                        if isSelected {
                            vm.settings.selectedCompanySizes.removeAll { $0 == size.rawValue }
                        } else {
                            vm.settings.selectedCompanySizes.append(size.rawValue)
                        }
                                            vm.refilterCompanies()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: size.icon).font(.caption2)
                            Text(size.shortName).font(.caption)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(isSelected ? Color.purple.opacity(0.8) : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                }
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
                Text("Companies").font(.headline)
                Spacer()
                Menu {
                                    Button(action: { vm.startFindCompanies() }) {
                        Label("Search (filtered by industry)", systemImage: "magnifyingglass")
                    }
                    Button(action: { showManualCompanySheet = true }) {
                        Label("Add company manually", systemImage: "plus.circle")
                    }
                    Divider()
                    Button(action: { vm.addTestCompany() }) {
                        Label("Add test company", systemImage: "flask")
                    }
                } label: { Label("Companies", systemImage: "plus") }
                .buttonStyle(.borderedProminent).disabled(vm.isLoading)
            }

            if vm.isLoading { Button("Cancel", role: .cancel) { vm.cancelOperation() }.buttonStyle(.bordered) }

            if !vm.errorMessage.isEmpty {
                HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(vm.errorMessage).font(.caption).foregroundStyle(.red) }
                .padding(8).background(Color.red.opacity(0.1)).cornerRadius(8)
            }

            if vm.companies.isEmpty {
                VStack { Spacer(); Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(.secondary); Text("No companies yet").font(.headline).foregroundStyle(.secondary); Spacer() }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(vm.companies) { company in
                        CompanyRow(company: company, hasContacts: vm.leads.contains { $0.company == company.name }, onFindContacts: { Task { await vm.findContacts(for: company) } }, onAddManual: { selectedCompanyForContact = company; showManualContactSheet = true })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).padding(16)
    }
}

// MARK: - Contact List (Right) - PER-SEARCH RESULTS
struct ProspectingContactList: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Results").font(.headline)
                Spacer()
                Text("\(vm.currentSearchContacts.count) found this search").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Search all companies") { Task { await vm.findContactsForAll() } }.disabled(vm.companies.isEmpty || vm.isLoading)
                Button("Verify all emails") { Task { await vm.verifyAllEmails() } }.disabled(vm.leads.isEmpty || vm.isLoading).buttonStyle(.borderedProminent).tint(.orange)
            }

            if vm.currentSearchContacts.isEmpty {
                VStack { Spacer(); Image(systemName: "person.2").font(.system(size: 48)).foregroundStyle(.secondary); Text("No contacts from current search").font(.headline).foregroundStyle(.secondary); Text("All found contacts are automatically added to Contacts tab").font(.caption).foregroundStyle(.tertiary); Spacer() }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(vm.currentSearchContacts) { lead in
                        LeadRowProspecting(lead: lead, onVerify: { Task { await vm.verifyEmail(for: lead.id) } })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).padding(16)
    }
}

// MARK: - Company Row (with employeeCount)
struct CompanyRow: View {
    let company: Company; let hasContacts: Bool; let onFindContacts: () -> Void; let onAddManual: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) { Text(company.name).font(.headline); if hasContacts { Image(systemName: "person.fill.checkmark").foregroundStyle(.green).font(.caption) } }
                HStack(spacing: 8) {
                    Text(company.industry).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.blue.opacity(0.1)).cornerRadius(4)
                    Text(company.region).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.green.opacity(0.1)).cornerRadius(4)
                    if company.employeeCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "person.3.fill").font(.caption2)
                            Text("\(company.employeeCount) MA").font(.caption)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.purple.opacity(0.1)).cornerRadius(4)
                    }
                }
                if !company.website.isEmpty { Text(company.website).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                Button(action: onFindContacts) { Label("Find contacts", systemImage: "magnifyingglass") }
                Button(action: onAddManual) { Label("Add contact manually", systemImage: "plus") }
            } label: { Text("Actions").font(.caption) }.controlSize(.small)
        }.padding(.vertical, 4)
    }
}

// MARK: - Lead Row
struct LeadRowProspecting: View {
    let lead: Lead; let onVerify: () -> Void

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
                            HStack(spacing: 2) { Image(systemName: lead.isManuallyCreated ? "person.crop.circle.badge.checkmark" : "checkmark.seal.fill").foregroundStyle(.green); Text(lead.isManuallyCreated ? "Manual" : "Verified").font(.caption2).bold().foregroundStyle(.green) }
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.green.opacity(0.15)).cornerRadius(4)
                        } else {
                            HStack(spacing: 2) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text("Not verified").font(.caption2).foregroundStyle(.orange) }
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.15)).cornerRadius(4)
                        }
                    }
                } else { Text("No email found").font(.caption).foregroundStyle(.red).italic() }
            }
            Spacer()
            if !lead.emailVerified && !lead.isManuallyCreated && !lead.email.isEmpty {
                Button("Verify") { onVerify() }.controlSize(.small).buttonStyle(.borderedProminent).tint(.orange)
            } else if lead.emailVerified || lead.isManuallyCreated {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            }
        }.padding(.vertical, 4)
    }
}

// MARK: - Manual Company Entry
struct ManualCompanyEntryView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var companyName = ""
    @State private var industry = Industry.Q_healthcare
    @State private var region = Region.dach
    @State private var website = ""
    @State private var companyDescription = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Company").font(.title2).bold()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape).buttonStyle(.bordered)
                Button("Add") {
                    let company = Company(name: companyName, industry: industry.rawValue, region: region.rawValue, website: website, description: companyDescription)
                    vm.addCompanyManually(company); dismiss()
                }.buttonStyle(.borderedProminent).disabled(companyName.isEmpty).keyboardShortcut(.return)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) { Text("Company Name *").font(.headline); TextField("e.g. Siemens AG", text: $companyName).textFieldStyle(.roundedBorder) }
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) { Text("Industry *").font(.headline); Picker("Industry", selection: $industry) { ForEach(Industry.allCases) { ind in Text(ind.rawValue).tag(ind) } }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading) }
                        VStack(alignment: .leading, spacing: 6) { Text("Region *").font(.headline); Picker("Region", selection: $region) { ForEach(Region.allCases) { reg in Text(reg.rawValue).tag(reg) } }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    VStack(alignment: .leading, spacing: 6) { Text("Website").font(.headline); TextField("https://www.example.com", text: $website).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 6) { Text("Description").font(.headline); TextEditor(text: $companyDescription).frame(minHeight: 80).border(Color.gray.opacity(0.3)) }
                }.padding(24)
            }
        }.frame(width: 700, height: 550)
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Add Contact").font(.title2).bold(); Text("Company: \(company.name)").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape).buttonStyle(.bordered)
                Button("Add") {
                    let lead = Lead(name: contactName, title: title, company: company.name, email: email, emailVerified: true, linkedInURL: linkedIn, responsibility: responsibility, status: .identified, source: "Manual entry", isManuallyCreated: true)
                    vm.addLeadManually(lead); dismiss()
                }.buttonStyle(.borderedProminent).disabled(contactName.isEmpty).keyboardShortcut(.return)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) { Text("Name *").font(.headline); TextField("Full name", text: $contactName).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 6) { Text("Title / Position").font(.headline); TextField("e.g. Chief Compliance Officer", text: $title).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email").font(.headline); TextField("name@company.com", text: $email).textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption); Text("Manual contacts skip email verification").font(.caption).foregroundStyle(.green) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) { Text("LinkedIn URL (optional)").font(.headline); TextField("https://linkedin.com/in/...", text: $linkedIn).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 6) { Text("Responsibility (optional)").font(.headline); TextEditor(text: $responsibility).frame(minHeight: 100).border(Color.gray.opacity(0.3)) }
                }.padding(24)
            }
        }.frame(minWidth: 700, idealWidth: 800, minHeight: 600, idealHeight: 700)
    }
}
