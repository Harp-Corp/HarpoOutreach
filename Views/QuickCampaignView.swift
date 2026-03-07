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
        "Branche & Region",
        "Prospecting",
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
            if currentStep == 2 {
                // Step 2 braucht feste Hoehe fuer HSplitView/TextEditor – kein ScrollView
                stepReviewSend
                    .padding(24)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        switch currentStep {
                        case 0: stepSelectFilters
                        case 1: stepProspecting
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
                if currentStep < 2 {
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
            ForEach(0..<3) { step in
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
                    if step < 2 {
                        Rectangle()
                            .fill(step < currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                ForEach(0..<3) { step in
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

    // MARK: - Step 1: Prospecting (Companies + Contacts + Drafts combined)
    private var stepProspecting: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading) {
                    Text("Prospecting")
                        .font(.headline)
                    Text("Suche nach Unternehmen, Kontakten und Email-Erstellung in \(selectedIndustries.count) Branchen, \(selectedRegions.count) Regionen")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                        Text(vm.currentStep)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if companiesFound > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2.fill").font(.caption).foregroundStyle(.indigo)
                            Text("\(companiesFound) Unternehmen gefunden")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if contactsFound > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.indigo)
                            Text("\(contactsFound) Kontakte gefunden")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if draftsCreated > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill").font(.caption).foregroundStyle(.cyan)
                            Text("\(draftsCreated) Emails erstellt")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.05))
                .cornerRadius(8)
            } else if contactsFound > 0 || companiesFound > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prospecting abgeschlossen")
                                .font(.headline)
                            Text("\(companiesFound) Unternehmen, \(contactsFound) Kontakte, \(draftsCreated) Emails erstellt")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)

                if !vm.leads.isEmpty {
                    GroupBox("Gefundene Kontakte (erste 8)") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(vm.leads.prefix(8)) { lead in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lead.name).font(.callout)
                                        Text(lead.email.isEmpty ? "Keine Email" : lead.email)
                                            .font(.caption2)
                                            .foregroundStyle(lead.email.isEmpty ? .red : .secondary)
                                    }
                                    Spacer()
                                    Text(lead.company).font(.caption).foregroundStyle(.secondary)
                                    if lead.draftedEmail != nil {
                                        Image(systemName: "envelope.fill")
                                            .font(.caption2).foregroundStyle(.cyan)
                                    }
                                }
                            }
                            if vm.leads.count > 8 {
                                Text("... und \(vm.leads.count - 8) weitere")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Klicke auf 'Weiter', um Unternehmen, Kontakte und Emails zu erstellen")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Sucht automatisch nach Unternehmen, deren Compliance-Ansprechpartnern und erstellt personalisierte Emails")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }

    // MARK: - Step 2: Review & Send
    @State private var reviewSelectedLeads: Set<UUID> = []
    @State private var reviewEditingLeadId: UUID? = nil
    @State private var editSubject: String = ""
    @State private var editBody: String = ""
    @State private var editEmail: String = ""
    @State private var sendResult: SendResult? = nil
    @State private var isSending = false
    @State private var batchResetConfirm = false

    // Manuellen Kontakt hinzufuegen
    @State private var showAddContact = false
    @State private var newContactName: String = ""
    @State private var newContactCompany: String = ""
    @State private var newContactEmail: String = ""

    /// Sende-Ergebnis fuer Feedback-Anzeige
    private struct SendResult {
        let sent: Int
        let failed: Int
        let total: Int
    }

    /// Unsubscribe-Footer der immer am Ende jeder Email stehen muss
    private static let unsubscribeFooter = "\n\n---\nWenn Sie keine weiteren Nachrichten erhalten möchten, antworten Sie mit 'Abbestellen' oder schreiben Sie an: unsubscribe@harpocrates-corp.com"

    /// Leads that have a draft and have NOT been sent yet
    private var draftLeads: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil && $0.dateEmailSent == nil }
    }

    /// Leads that have been successfully sent
    private var sentLeads: [Lead] {
        vm.leads.filter { $0.dateEmailSent != nil }
    }

    /// All campaign leads (drafts + sent)
    private var allCampaignLeads: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil }
    }

    private var stepReviewSend: some View {
        VStack(spacing: 0) {
            // Top bar: actions
            HStack(spacing: 12) {
                // Status-Zusammenfassung
                HStack(spacing: 4) {
                    if sentLeads.isEmpty {
                        Image(systemName: "envelope.badge").foregroundStyle(.blue)
                        Text("\(draftLeads.count) Emails bereit zum Senden")
                            .font(.callout.bold())
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(sentLeads.count) gesendet, \(draftLeads.count) noch offen")
                            .font(.callout.bold())
                    }
                }
                Spacer()

                // Alle auswaehlen / keine auswaehlen
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
                .disabled(draftLeads.isEmpty)

                // Alle zurücksetzen (Batch Reset)
                Button(action: { batchResetConfirm = true }) {
                    Label("Alle zurücksetzen", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(allCampaignLeads.isEmpty)
                .foregroundStyle(.orange)

                // Hauptaktion: Ausgewaehlte senden (freigeben + senden in einem Schritt)
                Button(action: { sendSelectedEmails() }) {
                    Label(
                        isSending ? "Wird gesendet..." : "Ausgewählte senden (\(reviewSelectedLeads.count))",
                        systemImage: "paperplane.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewSelectedLeads.isEmpty || isSending)
            }
            .padding(.bottom, 8)

            // Sende-Ergebnis: Erfolg oder Fehler
            if let result = sendResult {
                HStack(spacing: 6) {
                    if result.failed == 0 {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                        Text("\(result.sent) von \(result.total) Emails erfolgreich gesendet")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        Text("\(result.sent) gesendet, \(result.failed) fehlgeschlagen")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(action: { sendResult = nil }) {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sendResult?.failed == 0 ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                .cornerRadius(6)
                .padding(.bottom, 8)
            }

            // Sende-Fortschritt
            if isSending {
                HStack {
                    ProgressView()
                    Text(vm.currentStep.isEmpty ? "Emails werden gesendet..." : vm.currentStep)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
                .padding(.bottom, 8)
            }

            // Hinweis (nur wenn noch nichts gesendet wurde und kein Ergebnis da ist)
            if sendResult == nil && sentLeads.isEmpty && !isSending && !draftLeads.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.blue)
                    Text("Prüfe die Emails und klicke auf \"Ausgewählte senden\", um sie zu verschicken.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
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
                        if !sentLeads.isEmpty {
                            Text("\(sentLeads.count) gesendet")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if !draftLeads.isEmpty {
                            Text("\(draftLeads.count) offen")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()

                    // Inline-Formular fuer manuelles Hinzufuegen
                    if showAddContact {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Neuer Kontakt")
                                .font(.caption.bold())
                            TextField("Name", text: $newContactName)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            TextField("Firma", text: $newContactCompany)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            TextField("Email", text: $newContactEmail)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            HStack(spacing: 6) {
                                Button("Hinzufügen") {
                                    addManualContact()
                                }
                                .buttonStyle(.borderedProminent)
                                .font(.caption)
                                .disabled(newContactName.isEmpty || newContactEmail.isEmpty)
                                Button("Abbrechen") {
                                    showAddContact = false
                                    newContactName = ""
                                    newContactCompany = ""
                                    newContactEmail = ""
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.05))

                        Divider()
                    }

                    List(selection: Binding<UUID?>(get: { reviewEditingLeadId }, set: { newVal in
                        if let id = newVal {
                            DispatchQueue.main.async { selectLeadForEditing(id) }
                        }
                    })) {
                        // Noch nicht gesendete Leads (oben)
                        if !draftLeads.isEmpty {
                            Section {
                                ForEach(draftLeads) { lead in
                                    leadRow(lead: lead, isSent: false)
                                }
                            }
                        }
                        // Bereits gesendete Leads (unten, ausgegraut)
                        if !sentLeads.isEmpty {
                            Section {
                                ForEach(sentLeads) { lead in
                                    leadRow(lead: lead, isSent: true)
                                }
                            } header: {
                                Text("Gesendet")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .listStyle(.plain)

                    Divider()

                    Button(action: { showAddContact.toggle() }) {
                        Label(showAddContact ? "Formular schließen" : "Kontakt hinzufügen", systemImage: showAddContact ? "xmark" : "plus")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                .background(Color(nsColor: .controlBackgroundColor))

                // MARK: Right: Email Draft Editor
                VStack(spacing: 0) {
                    if let leadId = reviewEditingLeadId,
                       let lead = vm.leads.first(where: { $0.id == leadId }),
                       lead.draftedEmail != nil {

                        // Gesendete Email: Nur-Lesen-Ansicht
                        if lead.dateEmailSent != nil {
                            sentEmailView(lead: lead)
                        } else {
                            // Draft-Editor
                            draftEditorView(lead: lead)
                        }
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
                            Text("Wähle links einen Kontakt, um die Email zu prüfen oder zu bearbeiten.")
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
            reviewSelectedLeads = Set(draftLeads.map { $0.id })
            if let first = draftLeads.first {
                DispatchQueue.main.async { selectLeadForEditing(first.id) }
            }
        }
        .alert("Alle zurücksetzen?", isPresented: $batchResetConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Zurücksetzen", role: .destructive) {
                let ids = allCampaignLeads.map { $0.id }
                vm.resetBatch(ids: ids)
                reviewSelectedLeads.removeAll()
                reviewEditingLeadId = nil
                sendResult = nil
            }
        } message: {
            Text("Alle \(allCampaignLeads.count) Kampagnen-Leads werden komplett zurückgesetzt (Drafts, Senddaten und Blocklist-Einträge werden gelöscht). Diese Aktion kann nicht rückgängig gemacht werden.")
        }
    }

    // MARK: - Contact Row in List
    private func leadRow(lead: Lead, isSent: Bool) -> some View {
        HStack(spacing: 8) {
            // Checkbox nur fuer nicht-gesendete Leads
            if !isSent {
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
            } else {
                // Gesendet-Icon
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(lead.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(isSent ? .secondary : .primary)
                    if lead.isManuallyCreated {
                        Text("Manuell")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3)
                            .foregroundStyle(.green)
                    }
                }
                Text(lead.company.isEmpty ? lead.email : lead.company)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            // Reset / Resend buttons for sent leads
            if isSent {
                HStack(spacing: 4) {
                    // Erneut senden (soft reset, keeps draft)
                    Button(action: {
                        vm.resendLead(id: lead.id)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Erneut senden")

                    // Zurücksetzen (full reset)
                    Button(action: {
                        vm.resetLead(id: lead.id)
                        if reviewEditingLeadId == lead.id {
                            reviewEditingLeadId = nil
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundStyle(.red)
                    .help("Zurücksetzen")
                }
            } else {
                // Reset button for draft (non-sent) leads
                Button(action: {
                    vm.resetLead(id: lead.id)
                    reviewSelectedLeads.remove(lead.id)
                    if reviewEditingLeadId == lead.id {
                        reviewEditingLeadId = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Zurücksetzen")
            }

            if isSent {
                Text("Gesendet")
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(3)
                    .foregroundStyle(.green)
            } else if lead.deliveryStatus == .failed {
                Text("Fehler")
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(3)
                    .foregroundStyle(.red)
            }
        }
        .tag(lead.id)
        .contentShape(Rectangle())
    }

    // MARK: - Sent Email (read-only)
    private func sentEmailView(lead: Lead) -> some View {
        VStack(spacing: 0) {
            // Erfolgs-Banner mit Reset/Resend
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email erfolgreich gesendet")
                        .font(.callout.bold()).foregroundStyle(.green)
                    if let sentDate = lead.dateEmailSent {
                        Text("Gesendet am \(sentDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    // Thread ID indicator
                    if !lead.gmailThreadId.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2).foregroundStyle(.indigo)
                            Text("Thread: \(String(lead.gmailThreadId.prefix(16)))...")
                                .font(.caption2).foregroundStyle(.indigo)
                        }
                    }
                }
                Spacer()
                // Erneut senden
                Button(action: {
                    vm.resendLead(id: lead.id)
                }) {
                    Label("Erneut senden", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                // Zurücksetzen
                Button(action: {
                    vm.resetLead(id: lead.id)
                    reviewEditingLeadId = nil
                }) {
                    Label("Zurücksetzen", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
            .padding(12)
            .background(Color.green.opacity(0.08))

            Divider()

            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("An: \(lead.name)")
                            .font(.callout.bold())
                        Text(lead.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            // Subject (read-only)
            HStack {
                Text("Betreff:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(lead.draftedEmail?.subject ?? "")
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Body (read-only)
            ScrollView {
                Text(lead.draftedEmail?.body ?? "")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Draft Editor (editable)
    private func draftEditorView(lead: Lead) -> some View {
        VStack(spacing: 0) {
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

                    // Zurücksetzen im Draft-Editor
                    Button(action: {
                        vm.resetLead(id: lead.id)
                        reviewSelectedLeads.remove(lead.id)
                        reviewEditingLeadId = nil
                    }) {
                        Label("Zurücksetzen", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
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
                    DispatchQueue.main.async { saveCurrentDraft(lead: lead) }
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Spacer()

                // Einzelne Email direkt senden
                Button(action: {
                    DispatchQueue.main.async { saveCurrentDraft(lead: lead) }
                    Task {
                        isSending = true
                        vm.approveEmail(for: lead.id)
                        await vm.sendEmail(for: lead.id)
                        isSending = false
                        if let updated = vm.leads.first(where: { $0.id == lead.id }),
                           updated.dateEmailSent != nil {
                            sendResult = SendResult(sent: 1, failed: 0, total: 1)
                        } else {
                            sendResult = SendResult(sent: 0, failed: 1, total: 1)
                        }
                    }
                }) {
                    Label("Diese Email senden", systemImage: "paperplane")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || editEmail.isEmpty)
            }
            .padding(12)
        }
    }

    /// Alle ausgewaehlten Emails freigeben und senden
    private func sendSelectedEmails() {
        sendResult = nil
        isSending = true

        // Zuerst alle Drafts speichern (aktuell editierter Lead)
        if let currentId = reviewEditingLeadId,
           let currentLead = vm.leads.first(where: { $0.id == currentId }),
           currentLead.draftedEmail != nil {
            saveCurrentDraft(lead: currentLead)
        }

        // Alle ausgewaehlten freigeben
        DispatchQueue.main.async {
            for id in reviewSelectedLeads {
                vm.approveEmail(for: id)
            }
        }

        let selectedCount = reviewSelectedLeads.count
        Task {
            await vm.sendAllApproved()
            let newSentCount = vm.leads.filter { $0.dateEmailSent != nil }.count
            let sentInThisBatch = min(newSentCount, selectedCount)
            let failedInThisBatch = selectedCount - sentInThisBatch
            sendResult = SendResult(
                sent: sentInThisBatch,
                failed: failedInThisBatch,
                total: selectedCount
            )
            isSending = false
            // Auswahl aktualisieren: gesendete Leads aus der Auswahl entfernen
            reviewSelectedLeads = reviewSelectedLeads.filter { id in
                draftLeads.contains(where: { $0.id == id })
            }
        }
    }

    /// Fuegt einen manuellen Kontakt mit leerem Email-Draft hinzu
    private func addManualContact() {
        let lead = Lead(
            name: newContactName,
            company: newContactCompany,
            email: newContactEmail,
            emailVerified: false,
            status: .identified,
            source: "Quick Campaign - Manual",
            draftedEmail: OutboundEmail(
                subject: "",
                body: ""
            ),
            isManuallyCreated: true
        )
        vm.addLeadManually(lead)
        reviewSelectedLeads.insert(lead.id)
        DispatchQueue.main.async { selectLeadForEditing(lead.id) }
        newContactName = ""
        newContactCompany = ""
        newContactEmail = ""
        showAddContact = false
    }

    /// Speichert den aktuellen Draft inkl. Email-Adresse und sorgt fuer Unsubscribe-Footer
    private func saveCurrentDraft(lead: Lead) {
        if let index = vm.leads.firstIndex(where: { $0.id == lead.id }) {
            vm.leads[index].email = editEmail
        }
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
        if let prevId = reviewEditingLeadId,
           let prevLead = vm.leads.first(where: { $0.id == prevId }),
           prevLead.draftedEmail != nil,
           prevLead.dateEmailSent == nil {
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
            // Step 0 -> Step 1: Prospecting (Companies + Contacts + Drafts in einem Durchlauf)
            guard !selectedIndustries.isEmpty else { stepError = "Bitte Branche auswählen"; return }
            isRunning = true
            currentStep = nextStep
            Task {
                vm.settings.selectedRegions = selectedRegions.map { $0.rawValue }
                vm.settings.selectedIndustries = selectedIndustries.map { $0.rawValue }
                vm.settings.selectedCompanySizes = CompanySize.allCases.map { $0.rawValue }
                await vm.findCompaniesWithCancellation()
                companiesFound = vm.companies.count - beforeCompanies
                await vm.findContactsForAll()
                contactsFound = vm.leads.count - beforeLeads
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
