import SwiftUI

// MARK: - OutboundSingleView
// Feature 4: Outbound an einzelne Ansprechpartner
// 4.1 Generierung persoenliches Anschreiben (Unternehmenssituation, Position, Compliance, Harpocrates)
// 4.2 Draft Review durch User
// 4.3 Freigabe und Versand durch Nutzer

struct OutboundSingleView: View {
    @ObservedObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var selectedLead: Lead? = nil
    @State private var draftSubject = ""
    @State private var draftBody = ""
    @State private var isGenerating = false
    @State private var showDraftEditor = false
    @State private var generationError = ""

    // Filtered leads for selection
    private var selectableLeads: [Lead] {
        let active = vm.leads.filter { !$0.optedOut && $0.status != .doNotContact }
        if searchText.isEmpty { return active }
        let q = searchText.lowercased()
        return active.filter {
            $0.name.lowercased().contains(q) ||
            $0.company.lowercased().contains(q) ||
            $0.email.lowercased().contains(q) ||
            $0.title.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Einzelanschreiben")
                        .font(.largeTitle)
                        .bold()
                    Text("Personalisiertes Outbound an einzelne Kontakte")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            Divider()

            HSplitView {
                // Left: Contact Selection
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Kontakt suchen...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding()

                    List(selectableLeads, selection: $selectedLead) { lead in
                        OutboundContactRow(lead: lead, isSelected: selectedLead?.id == lead.id)
                            .tag(lead)
                            .onTapGesture { selectedLead = lead }
                    }
                }
                .frame(minWidth: 300, maxWidth: 400)

                // Right: Draft Generation & Editor
                VStack(spacing: 0) {
                    if let lead = selectedLead {
                        // Contact Info Header
                        contactInfoHeader(lead)
                        Divider()

                        if showDraftEditor {
                            // Draft Editor
                            draftEditorView(lead)
                        } else {
                            // Generate Button
                            generatePromptView(lead)
                        }
                    } else {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Waehle einen Kontakt aus der Liste")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Das Anschreiben wird personalisiert generiert basierend auf\nUnternehmenssituation, Position und Compliance-Status.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                }
                .frame(minWidth: 500)
            }
        }
    }

    // MARK: - Contact Info Header
    private func contactInfoHeader(_ lead: Lead) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                Text(String(lead.name.prefix(1)).uppercased())
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.name).font(.headline)
                if !lead.title.isEmpty {
                    Text(lead.title).font(.subheadline).foregroundColor(.secondary)
                }
                HStack {
                    Text(lead.company).font(.caption).foregroundColor(.secondary)
                    if !lead.email.isEmpty {
                        Text("|").foregroundColor(.secondary)
                        Text(lead.email).font(.caption).foregroundColor(.blue)
                    }
                }
            }
            Spacer()
            // Status Badge
            Text(lead.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }

    // MARK: - Generate Prompt View
    private func generatePromptView(_ lead: Lead) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Personalisiertes Anschreiben generieren")
                .font(.title3)
                .bold()

            Text("Perplexity analysiert Unternehmenssituation, Position,\nCompliance-Status der Branche und erstellt ein\nmassgeschneidertes Anschreiben fuer \(lead.name).")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !generationError.isEmpty {
                Text(generationError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Button(action: { generateDraft(for: lead) }) {
                if isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generiere...")
                    }
                } else {
                    Label("Anschreiben generieren", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isGenerating || lead.email.isEmpty)

            if lead.email.isEmpty {
                Text("Keine E-Mail-Adresse vorhanden")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Draft Editor
    private func draftEditorView(_ lead: Lead) -> some View {
        VStack(spacing: 0) {
            // Subject
            HStack {
                Text("Betreff:")
                    .font(.headline)
                    .frame(width: 70, alignment: .leading)
                TextField("Betreff", text: $draftSubject)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.top)

            // Body Editor
            VStack(alignment: .leading) {
                Text("Nachricht:")
                    .font(.headline)
                TextEditor(text: $draftBody)
                    .font(.body)
                    .frame(minHeight: 300)
                    .border(Color.gray.opacity(0.3))
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Opt-Out Footer Preview
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Opt-Out Link wird automatisch angefuegt")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            Spacer()

            // Action Buttons
            HStack {
                Button(action: {
                    showDraftEditor = false
                    draftSubject = ""
                    draftBody = ""
                }) {
                    Label("Verwerfen", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: { generateDraft(for: lead) }) {
                    Label("Neu generieren", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Spacer()

                Button(action: { saveDraft(for: lead) }) {
                    Label("Draft speichern", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button(action: { approveAndSend(lead) }) {
                    Label("Freigeben & Senden", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftSubject.isEmpty || draftBody.isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Actions
    private func generateDraft(for lead: Lead) {
        isGenerating = true
        generationError = ""
        Task {
            do {
                let result = try await vm.generatePersonalOutbound(for: lead)
                await MainActor.run {
                    draftSubject = result.subject
                    draftBody = result.body
                    showDraftEditor = true
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = "Fehler: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }

    private func saveDraft(for lead: Lead) {
        let email = OutboundEmail(subject: draftSubject, body: draftBody)
        vm.saveDraftForLead(leadId: lead.id, email: email)
    }

    private func approveAndSend(_ lead: Lead) {
        let email = OutboundEmail(subject: draftSubject, body: draftBody, isApproved: true)
        vm.approveAndSendSingle(leadId: lead.id, email: email)
        showDraftEditor = false
        draftSubject = ""
        draftBody = ""
        selectedLead = nil
    }
}

// MARK: - Outbound Contact Row
struct OutboundContactRow: View {
    let lead: Lead
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 36, height: 36)
                Text(String(lead.name.prefix(1)).uppercased())
                    .font(.subheadline.bold())
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(lead.company)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if lead.draftedEmail != nil {
                Image(systemName: "envelope.badge")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if lead.dateEmailSent != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
