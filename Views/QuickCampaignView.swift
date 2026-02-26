import SwiftUI

// MARK: - Quick Campaign Wizard
struct QuickCampaignView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var selectedIndustry: Industry?
    @State private var selectedRegion: Region?
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
            ScrollView {
                VStack(spacing: 0) {
                    switch currentStep {
                    case 0: stepSelectFilters
                    case 1: stepFindCompanies
                    case 2: stepFindContacts
                    case 3: stepDraftEmails
                    case 4: stepReviewSend
                    default: EmptyView()
                    }
                }
                .padding(24)
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
        .frame(width: 700, height: 580)
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
                        Button(action: { selectedIndustry = industry }) {
                            HStack {
                                Image(systemName: industry.icon)
                                Text(industry.shortName)
                                    .font(.callout)
                                Spacer()
                                if selectedIndustry == industry {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .background(selectedIndustry == industry ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedIndustry == industry ? Color.accentColor : Color.clear, lineWidth: 1.5)
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
                        Button(action: { selectedRegion = region }) {
                            HStack {
                                Text(region.rawValue)
                                    .font(.callout)
                                Spacer()
                                if selectedRegion == region {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .background(selectedRegion == region ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.07))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedRegion == region ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }

            if let industry = selectedIndustry {
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
                    if let industry = selectedIndustry, let region = selectedRegion {
                        Text("Suche nach \(industry.shortName)-Unternehmen in \(region.rawValue)")
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
    private var stepReviewSend: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                Text("Kampagne bereit")
                    .font(.headline)
            }

            // Summary boxes
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                WizardSummaryCard(
                    title: "Unternehmen",
                    value: "\(vm.statsCompanies)",
                    icon: "building.2.fill",
                    color: .indigo
                )
                WizardSummaryCard(
                    title: "Kontakte",
                    value: "\(vm.leads.count)",
                    icon: "person.2.fill",
                    color: .blue
                )
                WizardSummaryCard(
                    title: "Email Drafts",
                    value: "\(vm.statsDraftsReady)",
                    icon: "envelope.badge.fill",
                    color: .cyan
                )
            }

            GroupBox("Nächste Schritte") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "1.circle.fill").foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emails überprüfen").font(.callout.bold())
                            Text("Gehe zu Campaigns → Drafts und prüfe die erstellten Emails")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "2.circle.fill").foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emails freigeben").font(.callout.bold())
                            Text("Klicke auf 'Alle freigeben' oder genehmige Emails einzeln")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "3.circle.fill").foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kampagne versenden").font(.callout.bold())
                            Text("Klicke auf 'Alle senden' in der Outbox")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
            }

            if vm.statsDraftsReady > 0 {
                HStack(spacing: 12) {
                    Button(action: { vm.approveAllEmails() }) {
                        Label("Alle Emails freigeben (\(vm.statsDraftsReady))", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: { Task { await vm.sendAllApproved() } }) {
                        Label("Alle senden", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.statsApproved == 0 || vm.isLoading)
                }
            }

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Can Advance?
    private var canAdvance: Bool {
        switch currentStep {
        case 0: return selectedIndustry != nil && selectedRegion != nil
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
            // Just advance - filters selected
            currentStep = nextStep

        case 1:
            // Step 1 completed → auto-run find companies
            guard let industry = selectedIndustry else {
                stepError = "Bitte Branche auswählen"
                return
            }
            isRunning = true
            currentStep = nextStep
            Task {
                // Set the region filter before searching
                if let region = selectedRegion {
                    vm.selectedRegionFilter = region
                }
                vm.selectedIndustryFilter = industry
                vm.startFindCompanies(forIndustry: industry)
                // Wait for loading to complete
                while vm.isLoading {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                companiesFound = vm.companies.count - beforeCompanies
                isRunning = false
            }

        case 2:
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

        case 3:
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
