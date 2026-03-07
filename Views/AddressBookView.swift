import SwiftUI

// MARK: - AddressBookView
// Zeigt das neue Adressbuch (AddressBookEntry) sowie den bestehenden Firmen/Kontakt-Browser.
// Tabs:
//   0: Adressbuch (vm.addressBook - AddressBookEntry)
//   1: Firmen/Leads-Browser (original vm.companies / vm.leads)

struct AddressBookView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adressbuch")
                        .font(.largeTitle).bold()
                    Text("\(vm.statsAddressBook) Einträge | \(vm.statsAddressBookActive) aktiv | \(vm.statsBlocked) blockiert")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Adressbuch").tag(0)
                    Text("Firmen & Kontakte").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding()

            Divider()

            switch selectedTab {
            case 0:
                AddressBookMainView(vm: vm)
            case 1:
                AddressBookLegacyView(vm: vm)
            default:
                AddressBookMainView(vm: vm)
            }
        }
    }
}

// MARK: - Address Book Main View (AddressBookEntry-based)
struct AddressBookMainView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var statusFilter: String = "all" // "all" | "Active" | "Blocked"
    @State private var showAddEntry = false
    @State private var selectedEntry: AddressBookEntry? = nil
    @State private var deleteConfirmEntry: AddressBookEntry? = nil

    // Manual add form
    @State private var newName = ""
    @State private var newEmail = ""
    @State private var newTitle = ""
    @State private var newCompany = ""
    @State private var newPhone = ""
    @State private var newLinkedIn = ""
    @State private var newNotes = ""

    private var filteredEntries: [AddressBookEntry] {
        var result = vm.addressBook
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.company.lowercased().contains(q) ||
                $0.email.lowercased().contains(q) ||
                $0.title.lowercased().contains(q)
            }
        }
        if statusFilter != "all" {
            result = result.filter { $0.contactStatus == statusFilter }
        }
        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Suchen...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // Status filter
                Picker("Status", selection: $statusFilter) {
                    Text("Alle").tag("all")
                    Text("Aktiv").tag("Active")
                    Text("Blockiert").tag("Blocked")
                }
                .frame(width: 180)

                Spacer()

                // Alle verifizierten übernehmen
                Button(action: { vm.addAllVerifiedToAddressBook() }) {
                    Label("Alle verifizierten übernehmen", systemImage: "person.badge.clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                // Neuer Eintrag
                Button(action: { showAddEntry.toggle() }) {
                    Label("Neuer Eintrag", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Status message
            if !vm.statusMessage.isEmpty {
                HStack {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.caption)
                    Text(vm.statusMessage).font(.caption).foregroundStyle(.blue)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 4)
                .background(Color.blue.opacity(0.05))
            }

            Divider()

            HSplitView {
                // Left: Entry list
                VStack(spacing: 0) {
                    // Stats bar
                    HStack {
                        Text("\(filteredEntries.count) von \(vm.addressBook.count) Einträgen")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()

                    if filteredEntries.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("Keine Einträge gefunden")
                                .font(.callout).foregroundStyle(.secondary)
                            if vm.addressBook.isEmpty {
                                Text("Klicke auf 'Alle verifizierten übernehmen' oder 'Neuer Eintrag'.")
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List(selection: Binding<UUID?>(
                            get: { selectedEntry?.id },
                            set: { id in selectedEntry = vm.addressBook.first(where: { $0.id == id }) }
                        )) {
                            ForEach(filteredEntries) { entry in
                                addressBookRow(entry: entry)
                                    .tag(entry.id)
                            }
                        }
                        .listStyle(.plain)
                    }

                    // Inline Add Entry Form
                    if showAddEntry {
                        Divider()
                        addEntryForm
                    }
                }
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                .background(Color(nsColor: .controlBackgroundColor))

                // Right: Entry detail / edit
                VStack(spacing: 0) {
                    if let entry = selectedEntry,
                       let liveEntry = vm.addressBook.first(where: { $0.id == entry.id }) {
                        AddressBookDetailView(vm: vm, entry: liveEntry, onDelete: {
                            deleteConfirmEntry = liveEntry
                        })
                    } else {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("Eintrag auswählen")
                                .font(.callout).foregroundStyle(.secondary)
                            Text("Wähle links einen Kontakt, um Details zu sehen und zu bearbeiten.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minWidth: 380)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .alert("Eintrag dauerhaft löschen?", isPresented: Binding(
            get: { deleteConfirmEntry != nil },
            set: { if !$0 { deleteConfirmEntry = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { deleteConfirmEntry = nil }
            Button("Dauerhaft löschen", role: .destructive) {
                if let entry = deleteConfirmEntry {
                    vm.permanentlyDeleteFromAddressBook(entryId: entry.id)
                    if selectedEntry?.id == entry.id { selectedEntry = nil }
                    deleteConfirmEntry = nil
                }
            }
        } message: {
            Text("'\(deleteConfirmEntry?.name ?? "")' wird dauerhaft aus dem Adressbuch entfernt. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
    }

    // MARK: - Address Book Row
    private func addressBookRow(entry: AddressBookEntry) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(entry.contactStatus == "Blocked" ? Color.red.opacity(0.15) :
                          entry.optedOut ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(entry.name.prefix(1)).uppercased())
                    .font(.callout.bold())
                    .foregroundColor(entry.contactStatus == "Blocked" ? .red : .accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.callout).lineLimit(1)
                    if entry.contactStatus == "Blocked" {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2).foregroundStyle(.red)
                    } else if entry.emailVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2).foregroundStyle(.green)
                    }
                }
                Text(entry.email).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if !entry.company.isEmpty {
                    Text(entry.company).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            // Status badge
            contactStatusBadge(entry.contactStatus)
        }
        .padding(.vertical, 3)
        .opacity(entry.contactStatus == "Blocked" ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func contactStatusBadge(_ status: String) -> some View {
        Text(status == "Active" ? "Aktiv" : status == "Blocked" ? "Blockiert" : status)
            .font(.system(size: 9))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((status == "Active" ? Color.green : Color.red).opacity(0.12))
            .foregroundStyle(status == "Active" ? Color.green : Color.red)
            .cornerRadius(4)
    }

    // MARK: - Add Entry Form
    private var addEntryForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Neuer Adressbuch-Eintrag")
                    .font(.caption.bold())
                Spacer()
                Button(action: { showAddEntry = false; clearAddForm() }) {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }

            Group {
                TextField("Name *", text: $newName)
                TextField("Email *", text: $newEmail)
                TextField("Titel", text: $newTitle)
                TextField("Firma", text: $newCompany)
                TextField("Telefon", text: $newPhone)
                TextField("LinkedIn URL", text: $newLinkedIn)
            }
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            TextField("Notizen", text: $newNotes)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack {
                Button("Hinzufügen") {
                    addEntryManually()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .disabled(newName.isEmpty || newEmail.isEmpty)

                Button("Abbrechen") {
                    showAddEntry = false
                    clearAddForm()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.04))
    }

    private func addEntryManually() {
        let entry = AddressBookEntry(
            name: newName,
            title: newTitle,
            company: newCompany,
            email: newEmail,
            emailVerified: false,
            linkedInURL: newLinkedIn,
            phone: newPhone,
            notes: newNotes,
            source: "manual",
            contactStatus: "Active"
        )
        DatabaseService.shared.saveAddressBookEntry(entry)
        vm.loadAddressBook()
        selectedEntry = entry
        showAddEntry = false
        clearAddForm()
    }

    private func clearAddForm() {
        newName = ""; newEmail = ""; newTitle = ""; newCompany = ""
        newPhone = ""; newLinkedIn = ""; newNotes = ""
    }
}

// MARK: - Address Book Detail / Edit View
struct AddressBookDetailView: View {
    @ObservedObject var vm: AppViewModel
    let entry: AddressBookEntry
    let onDelete: () -> Void

    @State private var editName: String = ""
    @State private var editEmail: String = ""
    @State private var editTitle: String = ""
    @State private var editCompany: String = ""
    @State private var editPhone: String = ""
    @State private var editLinkedIn: String = ""
    @State private var editNotes: String = ""
    @State private var editStatus: String = "Active"
    @State private var isEditing = false
    @State private var blockConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(entry.contactStatus == "Blocked" ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(.title2.bold())
                        .foregroundColor(entry.contactStatus == "Blocked" ? .red : .accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.title3.bold())
                    HStack(spacing: 6) {
                        if !entry.title.isEmpty {
                            Text(entry.title).font(.caption).foregroundStyle(.secondary)
                            Text("@").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if !entry.company.isEmpty {
                            Text(entry.company).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        // Status badge
                        Text(entry.contactStatus == "Active" ? "Aktiv" : "Blockiert")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((entry.contactStatus == "Active" ? Color.green : Color.red).opacity(0.12))
                            .foregroundStyle(entry.contactStatus == "Active" ? Color.green : Color.red)
                            .cornerRadius(4)
                        // Verified badge
                        if entry.emailVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2).foregroundStyle(.green)
                            Text("Verifiziert").font(.system(size: 10)).foregroundStyle(.green)
                        }
                        // Source badge
                        Text(entry.source == "manual" ? "Manuell" : "Importiert")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Actions
                if !isEditing {
                    Button(action: { startEditing() }) {
                        Label("Bearbeiten", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    // Change status
                    if entry.contactStatus == "Active" {
                        Button(action: { blockConfirm = true }) {
                            Label("Blockieren", systemImage: "hand.raised")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.orange)
                    } else {
                        Button(action: {
                            vm.updateAddressBookStatus(entryId: entry.id, status: "Active")
                        }) {
                            Label("Aktivieren", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    // Permanent delete
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if isEditing {
                // Edit Form
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        editSection(title: "Kontaktdaten") {
                            VStack(spacing: 8) {
                                editRow(label: "Name", text: $editName)
                                editRow(label: "Email", text: $editEmail)
                                editRow(label: "Titel", text: $editTitle)
                                editRow(label: "Firma", text: $editCompany)
                                editRow(label: "Telefon", text: $editPhone)
                                editRow(label: "LinkedIn", text: $editLinkedIn)
                            }
                        }

                        editSection(title: "Status") {
                            Picker("Status", selection: $editStatus) {
                                Text("Aktiv").tag("Active")
                                Text("Blockiert").tag("Blocked")
                            }
                            .pickerStyle(.segmented)
                        }

                        editSection(title: "Notizen") {
                            TextEditor(text: $editNotes)
                                .font(.callout)
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }

                        HStack {
                            Button("Speichern") {
                                saveEdits()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(editName.isEmpty || editEmail.isEmpty)

                            Button("Abbrechen") {
                                isEditing = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                }
            } else {
                // Read-only detail
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        detailSection(title: "Kontaktdaten") {
                            VStack(alignment: .leading, spacing: 6) {
                                detailRow(label: "Email", value: entry.email)
                                if !entry.title.isEmpty { detailRow(label: "Titel", value: entry.title) }
                                if !entry.company.isEmpty { detailRow(label: "Firma", value: entry.company) }
                                if !entry.phone.isEmpty { detailRow(label: "Telefon", value: entry.phone) }
                                if !entry.linkedInURL.isEmpty { detailRow(label: "LinkedIn", value: entry.linkedInURL) }
                            }
                        }

                        detailSection(title: "Aktivität") {
                            VStack(alignment: .leading, spacing: 6) {
                                if let fc = entry.firstContacted {
                                    detailRow(label: "Erst kontaktiert", value: fc.formatted(date: .abbreviated, time: .omitted))
                                }
                                if let lc = entry.lastContacted {
                                    detailRow(label: "Zuletzt kontaktiert", value: lc.formatted(date: .abbreviated, time: .omitted))
                                }
                                detailRow(label: "Erstellt", value: entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                            }
                        }

                        if !entry.notes.isEmpty {
                            detailSection(title: "Notizen") {
                                Text(entry.notes)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { loadFromEntry() }
        .onChange(of: entry.id) { _, _ in loadFromEntry() }
        .alert("Kontakt blockieren?", isPresented: $blockConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Blockieren", role: .destructive) {
                vm.updateAddressBookStatus(entryId: entry.id, status: "Blocked")
            }
        } message: {
            Text("'\(entry.name)' wird als blockiert markiert und zur Blocklist hinzugefügt. Weitere Emails an \(entry.email) werden unterbunden.")
        }
    }

    private func loadFromEntry() {
        editName = entry.name
        editEmail = entry.email
        editTitle = entry.title
        editCompany = entry.company
        editPhone = entry.phone
        editLinkedIn = entry.linkedInURL
        editNotes = entry.notes
        editStatus = entry.contactStatus
        isEditing = false
    }

    private func startEditing() {
        loadFromEntry()
        isEditing = true
    }

    private func saveEdits() {
        // Save to DB directly via DatabaseService
        var updated = entry
        updated = AddressBookEntry(
            id: entry.id,
            name: editName,
            title: editTitle,
            company: editCompany,
            email: editEmail,
            emailVerified: entry.emailVerified,
            linkedInURL: editLinkedIn,
            phone: editPhone,
            notes: editNotes,
            source: entry.source,
            contactStatus: editStatus,
            optedOut: editStatus == "Blocked",
            firstContacted: entry.firstContacted,
            lastContacted: entry.lastContacted,
            createdAt: entry.createdAt,
            updatedAt: Date()
        )
        DatabaseService.shared.saveAddressBookEntry(updated)
        // Update status (handles blocklist sync)
        if editStatus != entry.contactStatus {
            vm.updateAddressBookStatus(entryId: entry.id, status: editStatus)
        } else {
            vm.loadAddressBook()
        }
        isEditing = false
    }

    // MARK: - Helpers
    @ViewBuilder
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func editSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func editRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text("\(label):").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.roundedBorder).font(.callout)
        }
    }
}

// MARK: - Legacy Companies/Contacts Browser (secondary tab)
struct AddressBookLegacyView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var selectedIndustryFilter: Industry? = nil
    @State private var selectedRegionFilter: Region? = nil
    @State private var showingAddCompany = false
    @State private var showingAddContact = false
    @State private var selectedCompany: Company? = nil
    @State private var viewMode: LegacyAddressBookMode = .companies

    enum LegacyAddressBookMode: String, CaseIterable {
        case companies = "Unternehmen"
        case contacts = "Kontakte"
    }

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

    private var totalCompanies: Int { vm.companies.count }
    private var totalContacts: Int { vm.leads.count }
    private var verifiedEmails: Int { vm.leads.filter { $0.emailVerified }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalCompanies) Unternehmen | \(totalContacts) Kontakte | \(verifiedEmails) verifiziert")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Suchen...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

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

            // Filter bar
            HStack(spacing: 16) {
                Picker("Ansicht", selection: $viewMode) {
                    ForEach(LegacyAddressBookMode.allCases, id: \.self) { mode in
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
                    ProgressView().scaleEffect(0.8)
                    Text(vm.currentStep).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch viewMode {
            case .companies:
                legacyCompaniesListView
            case .contacts:
                legacyContactsListView
            }
        }
        .sheet(isPresented: $showingAddCompany) {
            ManualEntryView(vm: vm)
        }
        .sheet(isPresented: $showingAddContact) {
            ManualEntryView(vm: vm)
        }
    }

    private var legacyCompaniesListView: some View {
        List {
            ForEach(filteredCompanies) { company in
                CompanyAddressRow(company: company, contactCount: contactsForCompany(company.name).count)
                    .onTapGesture { selectedCompany = company }
            }
            .onDelete { indexSet in
                let toDelete = indexSet.map { filteredCompanies[$0] }
                for company in toDelete { vm.deleteCompany(company) }
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

    private var legacyContactsListView: some View {
        List {
            ForEach(filteredContacts) { lead in
                HStack {
                    ContactAddressRow(lead: lead)
                    Spacer()
                    // "Ins Adressbuch" button for verified contacts
                    if lead.emailVerified {
                        Button(action: { vm.addLeadToAddressBook(leadId: lead.id) }) {
                            Label("Ins Adressbuch", systemImage: "person.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(DatabaseService.shared.addressBookEntryExists(email: lead.email))
                        .help(DatabaseService.shared.addressBookEntryExists(email: lead.email) ? "Bereits im Adressbuch" : "Zum Adressbuch hinzufügen")
                    }
                }
            }
            .onDelete { indexSet in
                let toDelete = indexSet.map { filteredContacts[$0] }
                for lead in toDelete { vm.deleteLead(lead.id) }
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
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !company.region.isEmpty {
                        Label(company.region, systemImage: "globe")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if company.employeeCount > 0 {
                        Label("\(company.employeeCount) MA", systemImage: "person.2")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(contactCount) Kontakte")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(contactCount > 0 ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                if !company.website.isEmpty {
                    Link(destination: URL(string: company.website.hasPrefix("http") ? company.website : "https://\(company.website)") ?? URL(string: "https://example.com")!) {
                        Image(systemName: "link").font(.caption)
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
                    Text(lead.name).font(.headline)
                    if lead.optedOut {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red).font(.caption)
                    }
                    if lead.emailVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green).font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    if !lead.title.isEmpty {
                        Text(lead.title).font(.caption).foregroundColor(.secondary)
                    }
                    Text("@ \(lead.company)").font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(lead.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor(lead.status).opacity(0.15))
                    .foregroundColor(statusColor(lead.status))
                    .cornerRadius(6)
                if !lead.email.isEmpty {
                    Text(lead.email).font(.caption2).foregroundColor(.secondary)
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
