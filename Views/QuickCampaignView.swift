import SwiftUI

// MARK: - Quick Campaign Wizard
struct QuickCampaignView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var selectedIndustries: Set<Industry> = []
    @State private var selectedRegions: Set<Region> = []
    @State private var isRunning = false
    @State private var stepError = ""
    @State private var companiesFound: Int = 0
    @State private var contactsFound: Int = 0
    @State private var draftsCreated: Int = 0

    private let stepTitles = [
        "Branche & Region wählen",
        "Unternehmen suchen",
        "Kontakte suchen",
        "Emails erstellen",
        "Prüfen & Senden"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Quick Campaign")
                    .font(.title2).bold()
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Step indicator
            stepIndicator
                .padding()

            Divider()

            // Step content
            if currentStep == 4 {
                // Step 4 braucht feste Hoehe fuer HSplitView/TextEditor – kein ScrollView
                stepReviewSend
                    .padding(24)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        switch currentStep {
                        case 0: stepSelectFilters
                        case 1: stepFindCompanies
                        case 2: stepFindContacts
                        case 3: stepDraftEmails
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                }
            }

            Divider()

            // Error message
            if !stepError.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(stepError).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("X") { stepError = "" }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
            }

            // Navigation buttons
            HStack {
                if currentStep > 0 && !isRunning {
                    Button("Zurück") { currentStep -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if currentStep < 4 {
                    Button("Weiter") { advanceStep() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || !canAdvance)
                } else {
                    Button("Fertig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 960, height: 680)
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { step in
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(step < currentStep ? Color.accentColor :
                                  step == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        if step < currentStep {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(step <= currentStep ? .white : .secondary)
                        }
                    }
                    if step < 4 {
                        Rectangle()
                            .fill(step < currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                ForEach(0..<5) { step in
                    Text(stepTitles[step])
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .offset(y: 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Step 0: Select Filters
    private var stepSelectFilters: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Branche auswählen")
                    .font(.headline)
                Text("Welche Branche soll für diese Kampagne prospektiert werden?")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Industry.allCases) { industry in
                        Button(action: { if selectedIndustries.contains(industry) { selectedIndustries.remove(industry) } else { selectedIndustries.insert(industry) } }) {
                            HStack {
                                Image(systemName: industry.icon)
                                Text(industry.shortName)
                                    .font(.callout)
                                Spacer()
                                if selectedIndustries.contains(industry) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 14).padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .background(selectedIndustries.contains(industry) ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedIndustries.contains(industry) ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Region auswählen")
                    .font(.headline)
                Text("In welcher Region soll gesucht werden?")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Region.allCases) { region in
                        Button(action: { if selectedRegions.contains(region) { selectedRegions.remove(region) } else { selectedRegions.insert(region) } }) {
                            HStack {
                                Text(region.rawValue)
                                    .font(.callout)
                                Spacer()
                                if selectedRegions.contains(region) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 14).padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .background(selectedRegions.contains(region) ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedRegions.contains(region) ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            if let industry = selectedIndustries.first, selectedIndustries.count == 1 {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Relevante Regulierungen für \(industry.shortName)")
                                .font(.caption.bold())
                        }
                        Text(industry.keyRegulations)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
            }
        }
    }

    // MARK: - Step 1: Find Companies
    private var stepFindCompanies: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading) {
                    Text("Unternehmen suchen")
                        .font(.headline)
                    if !selectedIndustries.isEmpty {
                        Text("Suche nach \(selectedIndustries.count) Branchen in \(selectedRegions.count) Regionen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if isRunning {
                HStack {
                    ProgressView()
                    Text(vm.currentStep)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.indigo.opacity(0.05))
                .cornerRadius(8)
            } else if companiesFound > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("\(companiesFound) Unternehmen gefunden")
                            .font(.headline)
                        Text("Bereit für die Kontaktsuche")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)

                if !vm.companies.isEmpty {
                    GroupBox("Gefundene Unternehmen (erste 5)") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(vm.companies.prefix(5)) { company in
                                HStack {
                                    Text(company.name).font(.callout)
                                    Spacer()
                                    Text(company.region).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if vm.companies.count > 5 {
                                Text("... und \(vm.companies.count - 5) weitere")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Klicke auf 'Weiter', um die Suche zu starten")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }

    // MARK: - Step 2: Find Contacts
    private var stepFindContacts: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Kontakte suchen")
                        .font(.headline)
                    Text("Suche Compliance-Ansprechpartner bei \(vm.companies.count) Unternehmen")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isRunning {
                HStack {
                    ProgressView()
                    Text(vm.currentStep)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            } else if contactsFound > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("\(contactsFound) Kontakte gefunden")
                            .font(.headline)
                        Text("Emails werden im nächsten Schritt erstellt")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)

                if !vm.leads.isEmpty {
                    GroupBox("Neue Kontakte (erste 5)") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(vm.leads.prefix(5)) { lead in
                                HStack {
                                    Text(lead.name).font(.callout)
                                    Spacer()
                                    Text(lead.company).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if vm.leads.count > 5 {
                                Text("... und \(vm.leads.count - 5) weitere")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Klicke auf 'Weiter', um Kontakte zu suchen")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }

    // MARK: - Step 3: Draft Emails
    private var stepDraftEmails: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "envelope.badge.fill")
                    .font(.title2).foregroundStyle(.cyan)
                VStack(alignment: .leading) {
                    Text("Emails erstellen")
                        .font(.headline)
                    Text("KI erstellt personalisierte Outreach-Emails für \(vm.leads.filter { $0.emailVerified || $0.isManuallyCreated }.count) Kontakte")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isRunning {
                HStack {
                    ProgressView()
                    Text(vm.currentStep)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.cyan.opacity(0.05))
                .cornerRadius(8)
            } else if draftsCreated > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("\(draftsCreated) Email-Drafts erstellt")
                            .font(.headline)
                        Text("Bitte überprüfen und freigeben im nächsten Schritt")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Klicke auf 'Weiter', um Emails zu erstellen")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Die KI erstellt personalisierte Emails basierend auf aktuellen Compliance-Herausforderungen")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }

    // MARK: - Step 4: Review & Send
    @State private var reviewSelectedLeads: Set<UUID> = []
    @State private var reviewEditingLeadId: UUID? = nil
    @State private var editSubject: String = ""
    @State private var editBody: String = ""
    @State private var editEmail: String = ""

    /// Unsubscribe-Footer der immer am Ende jeder Email stehen muss
    private static let unsubscribeFooter = "\n\n---\nWenn Sie keine weiteren Nachrichten erhalten möchten, antworten Sie mit 'Abbestellen' oder schreiben Sie an: unsubscribe@harpocrates-corp.com"

    /// Leads that have a draft (eligible for this campaign step)
    private var draftLeads: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }
    }

    private var stepReviewSend: some View {
        VStack(spacing: 0) {
            // Top bar: summary + actions
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(reviewSelectedLeads.count) von \(draftLeads.count) ausgewählt")
                        .font(.callout.bold())
                }
                Spacer()
                Button(action: {
                    if reviewSelectedLeads.count == draftLeads.count {
                        reviewSelectedLeads.removeAll()
                    } else {
                        reviewSelectedLeads = Set(draftLeads.map { $0.id })
                    }
                }) {
                    Text(reviewSelectedLeads.count == draftLeads.count ? "Keine auswählen" : "Alle auswählen")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    for id in reviewSelectedLeads {
                        vm.approveEmail(for: id)
                    }
                }) {
                    Label("Auswahl freigeben (\(reviewSelectedLeads.count))", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(reviewSelectedLeads.isEmpty)

                Button(action: { Task { await vm.sendAllApproved() } }) {
                    Label("Freigegebene senden", systemImage: "paperplane.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.statsApproved == 0 || vm.isLoading)
            }
            .padding(.bottom, 12)

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.bottom, 8)
            }

            // Split view: left = contact list, right = email editor
            HSplitView {
                // MARK: Left: Contact List
                VStack(spacing: 0) {
                    HStack {
                        Text("Kontakte")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(draftLeads.count) Drafts")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()

                    List(selection: Binding<UUID?>(get: { reviewEditingLeadId }, set: { newVal in
                        if let id = newVal { selectLeadForEditing(id) }
                    })) {
                        ForEach(draftLeads) { lead in
                            HStack(spacing: 8) {
                                // Checkbox for campaign inclusion
                                Button(action: {
                                    if reviewSelectedLeads.contains(lead.id) {
                                        reviewSelectedLeads.remove(lead.id)
                                    } else {
                                        reviewSelectedLeads.insert(lead.id)
                                    }
                                }) {
                                    Image(systemName: reviewSelectedLeads.contains(lead.id)
                                          ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(reviewSelectedLeads.contains(lead.id) ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lead.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text(lead.company)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()

                                // Status badge
                                if lead.draftedEmail?.isApproved == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .tag(lead.id)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                .background(Color(nsColor: .controlBackgroundColor))

                // MARK: Right: Email Draft Editor
                VStack(spacing: 0) {
                    if let leadId = reviewEditingLeadId,
                       let lead = vm.leads.first(where: { $0.id == leadId }),
                       lead.draftedEmail != nil {
                        // Header mit editierbarer Email-Adresse
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("An: \(lead.name)")
                                        .font(.callout.bold())
                                    HStack(spacing: 4) {
                                        Text("Email:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("Email-Adresse", text: $editEmail)
                                            .textFieldStyle(.plain)
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Text(lead.company)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.indigo.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(12)

                        Divider()

                        // Subject
                        HStack {
                            Text("Betreff:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            TextField("Betreff", text: $editSubject)
                                .textFieldStyle(.plain)
                                .font(.callout)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider()

                        // Body editor
                        TextEditor(text: $editBody)
                            .font(.callout)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        // Unsubscribe-Hinweis
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Unsubscribe-Footer wird automatisch angehängt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.05))

                        Divider()

                        // Draft action bar
                        HStack {
                            Button("Änderungen speichern") {
                                saveCurrentDraft(lead: lead)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Spacer()

                            if lead.draftedEmail?.isApproved == true {
                                Label("Freigegeben", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button(action: {
                                    saveCurrentDraft(lead: lead)
                                    vm.approveEmail(for: lead.id)
                                }) {
                                    Label("Freigeben", systemImage: "checkmark.seal")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                        .padding(12)
                    } else {
                        // Empty state
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "envelope.open")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Kontakt auswählen")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Wähle links einen Kontakt, um den Email-Draft zu bearbeiten.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minWidth: 350)
                .background(Color(nsColor: .textBackgroundColor))
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .onAppear {
            // Pre-select all leads with drafts
            reviewSelectedLeads = Set(draftLeads.map { $0.id })
            // Auto-select first lead for editing
            if let first = draftLeads.first {
                selectLeadForEditing(first.id)
            }
        }
    }

    /// Speichert den aktuellen Draft inkl. Email-Adresse und sorgt fuer Unsubscribe-Footer
    private func saveCurrentDraft(lead: Lead) {
        // Email-Adresse aktualisieren
        if let index = vm.leads.firstIndex(where: { $0.id == lead.id }) {
            vm.leads[index].email = editEmail
        }
        // Body mit Unsubscribe-Footer sicherstellen
        let bodyToSave = ensureUnsubscribeFooter(editBody)
        vm.updateDraft(for: lead, subject: editSubject, body: bodyToSave)
    }

    /// Stellt sicher, dass der Unsubscribe-Footer immer am Ende des Body steht
    private func ensureUnsubscribeFooter(_ text: String) -> String {
        let marker = "unsubscribe@harpocrates-corp.com"
        if text.contains(marker) {
            return text
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + Self.unsubscribeFooter
    }

    private func selectLeadForEditing(_ id: UUID) {
        // Save current edits before switching
        if let prevId = reviewEditingLeadId,
           let prevLead = vm.leads.first(where: { $0.id == prevId }),
           prevLead.draftedEmail != nil {
            saveCurrentDraft(lead: prevLead)
        }
        reviewEditingLeadId = id
        if let lead = vm.leads.first(where: { $0.id == id }),
           let draft = lead.draftedEmail {
            editSubject = draft.subject
            editBody = draft.body
            editEmail = lead.email
        }
    }

    // MARK: - Can Advance?
    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !selectedIndustries.isEmpty && !selectedRegions.isEmpty
        default: return true
        }
    }

    // MARK: - Advance Step Logic
    private func advanceStep() {
        stepError = ""
        let beforeCompanies = vm.companies.count
        let beforeLeads = vm.leads.count
        let beforeDrafts = vm.statsDraftsReady

        let nextStep = currentStep + 1

        switch currentStep {
        case 0:
            // Step 1 completed → auto-run find companies
            guard !selectedIndustries.isEmpty else { stepError = "Bitte Branche auswählen"; return }
            isRunning = true
            currentStep = nextStep
            Task {
                // Set the region filter before searching
                if true {
                    vm.settings.selectedRegions = selectedRegions.map { $0.rawValue }
                }
                vm.settings.selectedIndustries = selectedIndustries.map { $0.rawValue }
                                    vm.settings.selectedCompanySizes = CompanySize.allCases.map { $0.rawValue }
                        await vm.findCompaniesWithCancellation()            
                companiesFound = vm.companies.count - beforeCompanies
                isRunning = false
            }

        case 1:
            // Step 2 completed → auto-run find contacts
            guard !vm.companies.isEmpty else {
                stepError = "Keine Unternehmen gefunden. Bitte zurück und erneut versuchen."
                return
            }
            isRunning = true
            currentStep = nextStep
            Task {
                await vm.findContactsForAll()
                contactsFound = vm.leads.count - beforeLeads
                isRunning = false
            }

        case 2:
            // Step 3 completed → auto-run draft emails
            guard !vm.leads.isEmpty else {
                stepError = "Keine Kontakte gefunden. Bitte zurück und erneut versuchen."
                return
            }
            isRunning = true
            currentStep = nextStep
            Task {
                await vm.draftAllEmails()
                draftsCreated = vm.statsDraftsReady - beforeDrafts
                isRunning = false
            }

        default:
            currentStep = nextStep
        }
    }
}

// MARK: - Wizard Summary Card
struct WizardSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}
