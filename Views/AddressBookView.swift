import SwiftUI

// MARK: - AddressBookView
// Feature 1: Suche nach Unternehmen und Ansprechpartnern - Aufbau Adressbuch
// Zeigt gespeicherte Unternehmen und deren Kontakte (Leads) als durchsuchbares Adressbuch.
// Erlaubt gezieltes Suchen, Filtern und manuelles Hinzufuegen.

struct AddressBookView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var selectedIndustryFilter: Industry? = nil
    @State private var selectedRegionFilter: Region? = nil
    @State private var showingAddCompany = false
    @State private var showingAddContact = false
    @State private var selectedCompany: Company? = nil
    @State private var viewMode: AddressBookMode = .companies

    enum AddressBookMode: String, CaseIterable {
        case companies = "Unternehmen"
        case contacts = "Kontakte"
    }

    // MARK: - Filtered Data
    private var filteredCompanies: [Company] {
        var result = vm.companies
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.industry.lowercased().contains(query) ||
                $0.country.lowercased().contains(query) ||
                $0.naceCode.lowercased().contains(query)
            }
        }
        if let industry = selectedIndustryFilter {
            result = result.filter { $0.industry.contains(industry.naceSection) || $0.industry == industry.rawValue }
        }
        if let region = selectedRegionFilter {
            result = result.filter { $0.region == region.rawValue }
        }
        return result
    }

    private var filteredContacts: [Lead] {
        var result = vm.leads
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.company.lowercased().contains(query) ||
                $0.email.lowercased().contains(query) ||
                $0.title.lowercased().contains(query)
            }
        }
        if let industry = selectedIndustryFilter {
            let companyNames = Set(filteredCompanies.map { $0.name.lowercased() })
            result = result.filter { companyNames.contains($0.company.lowercased()) }
        }
        return result
    }

    // MARK: - Stats
    private var totalCompanies: Int { vm.companies.count }
    private var totalContacts: Int { vm.leads.count }
    private var verifiedEmails: Int { vm.leads.filter { $0.emailVerified }.count }
    private var optedOutCount: Int { vm.leads.filter { $0.optedOut }.count }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adressbuch")
                        .font(.largeTitle)
                        .bold()
                    Text("\(totalCompanies) Unternehmen | \(totalContacts) Kontakte | \(verifiedEmails) verifiziert")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Suchen...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // Actions
                Button(action: { showingAddCompany = true }) {
                    Label("Unternehmen", systemImage: "building.2.badge.plus")
                }
                .buttonStyle(.bordered)

                Button(action: { showingAddContact = true }) {
                    Label("Kontakt", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)

                Button(action: { vm.startFindCompanies() }) {
                    Label("Suche starten", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading)
            }
            .padding()

            Divider()

            // MARK: - Filter Bar
            HStack(spacing: 16) {
                Picker("Ansicht", selection: $viewMode) {
                    ForEach(AddressBookMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Picker("Branche", selection: $selectedIndustryFilter) {
                    Text("Alle Branchen").tag(nil as Industry?)
                    ForEach(Industry.allCases) { industry in
                        Text(industry.shortName).tag(industry as Industry?)
                    }
                }
                .frame(width: 180)

                Picker("Region", selection: $selectedRegionFilter) {
                    Text("Alle Regionen").tag(nil as Region?)
                    ForEach(Region.allCases) { region in
                        Text(region.rawValue).tag(region as Region?)
                    }
                }
                .frame(width: 150)

                Spacer()

                if vm.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(vm.currentStep)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // MARK: - Content
            switch viewMode {
            case .companies:
                companiesListView
            case .contacts:
                contactsListView
            }
        }
        .sheet(isPresented: $showingAddCompany) {
            ManualEntryView(vm: vm)
        }
        .sheet(isPresented: $showingAddContact) {
            ManualEntryView(vm: vm)
        }
    }

    // MARK: - Companies List
    private var companiesListView: some View {
        List {
            ForEach(filteredCompanies) { company in
                CompanyAddressRow(company: company, contactCount: contactsForCompany(company.name).count)
                    .onTapGesture {
                        selectedCompany = company
                    }
            }
            .onDelete { indexSet in
                let toDelete = indexSet.map { filteredCompanies[$0] }
                for company in toDelete {
                    vm.deleteCompany(company)
                }
            }
        }
        .overlay {
            if filteredCompanies.isEmpty {
                ContentUnavailableView(
                    "Keine Unternehmen",
                    systemImage: "building.2",
                    description: Text("Starte eine Suche oder fuege manuell hinzu.")
                )
            }
        }
    }

    // MARK: - Contacts List
    private var contactsListView: some View {
        List {
            ForEach(filteredContacts) { lead in
                ContactAddressRow(lead: lead)
            }
            .onDelete { indexSet in
                let toDelete = indexSet.map { filteredContacts[$0] }
                for lead in toDelete {
                    vm.deleteLead(lead)
                }
            }
        }
        .overlay {
            if filteredContacts.isEmpty {
                ContentUnavailableView(
                    "Keine Kontakte",
                    systemImage: "person.2",
                    description: Text("Suche nach Unternehmen und finde Ansprechpartner.")
                )
            }
        }
    }

    // MARK: - Helpers
    private func contactsForCompany(_ companyName: String) -> [Lead] {
        vm.leads.filter { $0.company.lowercased() == companyName.lowercased() }
    }
}

// MARK: - Company Row
struct CompanyAddressRow: View {
    let company: Company
    let contactCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(company.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if !company.industry.isEmpty {
                        Label(company.industry, systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !company.region.isEmpty {
                        Label(company.region, systemImage: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if company.employeeCount > 0 {
                        Label("\(company.employeeCount) MA", systemImage: "person.2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(contactCount) Kontakte")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(contactCount > 0 ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                if !company.website.isEmpty {
                    Link(destination: URL(string: company.website.hasPrefix("http") ? company.website : "https://\(company.website)") ?? URL(string: "https://example.com")!) {
                        Image(systemName: "link")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contact Row
struct ContactAddressRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(lead.optedOut ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(String(lead.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(lead.optedOut ? .red : .accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lead.name)
                        .font(.headline)
                    if lead.optedOut {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    if lead.emailVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    if !lead.title.isEmpty {
                        Text(lead.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("@ \(lead.company)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(lead.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(lead.status).opacity(0.15))
                    .foregroundColor(statusColor(lead.status))
                    .cornerRadius(6)
                if !lead.email.isEmpty {
                    Text(lead.email)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(lead.optedOut ? 0.6 : 1.0)
    }

    private func statusColor(_ status: LeadStatus) -> Color {
        switch status {
        case .identified: return .blue
        case .contacted, .emailSent: return .orange
        case .replied: return .green
        case .qualified, .converted: return .green
        case .notInterested, .doNotContact: return .red
        case .closed: return .gray
        default: return .secondary
        }
    }
}
