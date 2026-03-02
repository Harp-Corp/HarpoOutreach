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
                ProspectingCompanyList(
                    vm: vm,
                    showManualCompanySheet: $showManualCompanySheet,
                    showManualContactSheet: $showManualContactSheet,
                    selectedCompanyForContact: $selectedCompanyForContact
                )
                Divider()
                ProspectingContactList(vm: vm)
            }
        }
        .sheet(isPresented: $showManualCompanySheet) {
            ManualCompanyEntryView(vm: vm)
        }
        .sheet(isPresented: $showManualContactSheet, onDismiss: {
            selectedCompanyForContact = nil
        }) {
            Group {
                if let company = selectedCompanyForContact {
                    ManualContactEntryView(vm: vm, company: company)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kein Unternehmen ausgewaehlt.")
                        Text("Bitte in der Company-Liste einen Kontakt fuer ein Unternehmen hinzufuegen.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                }
            }
        }
    }
}

// MARK: - Multi-Select Filter Toggle Button
struct FilterToggleButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header with Multi-Select Filters
struct ProspectingHeaderView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prospecting")
                        .font(.title2)
                        .bold()
                    if !vm.currentStep.isEmpty {
                        Text(vm.currentStep)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !vm.statusMessage.isEmpty {
                        Text(vm.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !vm.errorMessage.isEmpty {
                        Text(vm.errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Button(action: {
                    if vm.isLoading {
                        vm.cancelSearch()
                    } else {
                        vm.startFindCompanies()
                    }
                }) {
                    Text(vm.isLoading ? "Suche abbrechen" : "Start Suche")
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isLoading ? Color.red : Color.accentColor)
            }

            // MARK: Industry Multi-Select
            VStack(alignment: .leading, spacing: 4) {
                Text("Branche").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(Industry.allCases, id: \.self) { ind in
                        FilterToggleButton(
                            title: ind.shortName,
                            isSelected: vm.settings.selectedIndustries.contains(ind.rawValue)
                        ) {
                            if vm.settings.selectedIndustries.contains(ind.rawValue) {
                                vm.settings.selectedIndustries.removeAll { $0 == ind.rawValue }
                            } else {
                                vm.settings.selectedIndustries.append(ind.rawValue)
                            }
                        }
                    }
                }
            }

            // MARK: Region Multi-Select
            VStack(alignment: .leading, spacing: 4) {
                Text("Region").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(Region.allCases, id: \.self) { reg in
                        FilterToggleButton(
                            title: reg.rawValue,
                            isSelected: vm.settings.selectedRegions.contains(reg.rawValue)
                        ) {
                            if vm.settings.selectedRegions.contains(reg.rawValue) {
                                vm.settings.selectedRegions.removeAll { $0 == reg.rawValue }
                            } else {
                                vm.settings.selectedRegions.append(reg.rawValue)
                            }
                        }
                    }
                }
            }

            // MARK: Size Multi-Select
            VStack(alignment: .leading, spacing: 4) {
                Text("Groesse").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(CompanySize.allCases, id: \.self) { size in
                        FilterToggleButton(
                            title: size.shortName,
                            isSelected: vm.settings.selectedCompanySizes.contains(size.rawValue)
                        ) {
                            if vm.settings.selectedCompanySizes.contains(size.rawValue) {
                                vm.settings.selectedCompanySizes.removeAll { $0 == size.rawValue }
                            } else {
                                vm.settings.selectedCompanySizes.append(size.rawValue)
                            }
                        }
                    }
                }
            }

            Button("Filter anwenden") {
                vm.refilterCompanies()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }
}

// MARK: - FlowLayout (wrapping HStack)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxHeight = y + rowHeight
        }
        return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Company List
struct ProspectingCompanyList: View {
    @ObservedObject var vm: AppViewModel
    @Binding var showManualCompanySheet: Bool
    @Binding var showManualContactSheet: Bool
    @Binding var selectedCompanyForContact: Company?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                if vm.companies.isEmpty {
                    Text("Keine Companies. Starte die Suche oder fuege manuell hinzu.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.companies.indices, id: \.self) { idx in
                        let company = vm.companies[idx]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(company.name)
                                .font(.headline)
                            HStack(spacing: 10) {
                                if !company.industry.isEmpty {
                                    Text(company.industry)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                if !company.region.isEmpty {
                                    Text(company.region)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            HStack(spacing: 8) {
                                Button("Kontakte suchen") {
                                    Task { await vm.findContacts(for: company) }
                                }
                                .buttonStyle(.bordered)
                                Button("Kontakt hinzufuegen") {
                                    selectedCompanyForContact = company
                                    showManualContactSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(minWidth: 420)
    }

    private var header: some View {
        HStack {
            Text("Companies (\(vm.companies.count))")
                .font(.headline)
            Spacer()
            Button("Manuell") { showManualCompanySheet = true }
                .buttonStyle(.bordered)
        }
        .padding(12)
    }
}

// MARK: - Contact List
struct ProspectingContactList: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                if vm.leads.isEmpty {
                    Text("Keine Kontakte.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.leads.indices, id: \.self) { idx in
                        let lead = vm.leads[idx]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lead.name)
                                .font(.headline)
                            Text(lead.company)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Text(lead.email)
                                    .font(.caption)
                                Text(lead.emailVerified ? "Verified" : "Unverified")
                                    .font(.caption)
                                    .foregroundStyle(lead.emailVerified ? .green : .orange)
                            }
                            if !lead.emailVerified {
                                Button("Verify") {
                                    Task { await vm.verifyEmail(for: lead.id) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(minWidth: 420)
    }

    private var header: some View {
        HStack {
            Text("Kontakte (\(vm.leads.count))")
                .font(.headline)
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Manual Company Entry
struct ManualCompanyEntryView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var companyName = ""
    @State private var industry: Industry = .Q_healthcare
    @State private var region: Region = .dach
    @State private var website = ""
    @State private var companyDescription = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Unternehmen hinzufuegen")
                .font(.title2)
                .bold()
            TextField("Firmenname*", text: $companyName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Picker("Branche", selection: $industry) {
                    ForEach(Industry.allCases, id: \.self) { ind in
                        Text(ind.rawValue).tag(ind)
                    }
                }
                .pickerStyle(.menu)
                Picker("Region", selection: $region) {
                    ForEach(Region.allCases, id: \.self) { reg in
                        Text(reg.rawValue).tag(reg)
                    }
                }
                .pickerStyle(.menu)
            }
            TextField("Website", text: $website)
                .textFieldStyle(.roundedBorder)
            TextField("Beschreibung", text: $companyDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                Spacer()
                Button("Speichern") {
                    let company = Company(
                        name: companyName,
                        industry: industry.rawValue,
                        region: region.rawValue,
                        website: website,
                        description: companyDescription
                    )
                    vm.addCompanyManually(company)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

// MARK: - Manual Contact Entry
struct ManualContactEntryView: View {
    @ObservedObject var vm: AppViewModel
    let company: Company
    @Environment(\.dismiss) private var dismiss
    @State private var contactName = ""
    @State private var contactTitle = ""
    @State private var contactEmail = ""
    @State private var linkedInURL = ""
    @State private var responsibility = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Kontakt hinzufuegen")
                .font(.title2)
                .bold()
            Text(company.name)
                .foregroundStyle(.secondary)
            TextField("Name*", text: $contactName)
                .textFieldStyle(.roundedBorder)
            TextField("Position", text: $contactTitle)
                .textFieldStyle(.roundedBorder)
            TextField("E-Mail*", text: $contactEmail)
                .textFieldStyle(.roundedBorder)
            TextField("LinkedIn URL", text: $linkedInURL)
                .textFieldStyle(.roundedBorder)
            TextField("Verantwortungsbereich", text: $responsibility, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                Spacer()
                Button("Speichern") {
                    let lead = Lead(
                        name: contactName,
                        title: contactTitle,
                        company: company.name,
                        email: contactEmail,
                        emailVerified: false,
                        linkedInURL: linkedInURL,
                        responsibility: responsibility,
                        status: .identified,
                        source: "Manual Entry",
                        isManuallyCreated: true
                    )
                    vm.addLeadManually(lead)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

#Preview {
    ProspectingView(vm: AppViewModel())
}
