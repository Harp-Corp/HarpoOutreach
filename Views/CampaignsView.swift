import SwiftUI

// MARK: - CampaignsView: Combined Email Drafts + Outbox + Inbox/Follow-Up
struct CampaignsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedSegment = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with segment picker
            HStack {
                Text("Campaigns").font(.largeTitle).bold()
                Spacer()
                Picker("", selection: $selectedSegment) {
                    Text("Drafts (\(vm.statsDraftsReady))").tag(0)
                    Text("Outbox (\(vm.statsApproved))").tag(1)
                    Text("Inbox (\(vm.replies.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
            }
            .padding()

            Divider()

            // Content based on segment
            switch selectedSegment {
            case 0: EmailDraftContent(vm: vm)
            case 1: OutboxContent(vm: vm)
            case 2: InboxContent(vm: vm)
            default: EmailDraftContent(vm: vm)
            }
        }
    }
}

// MARK: - Email Draft Content (extracted from EmailDraftView)
struct EmailDraftContent: View {
    @ObservedObject var vm: AppViewModel

    var draftsNeeded: [Lead] {
        vm.leads.filter { ($0.emailVerified || $0.isManuallyCreated) && $0.draftedEmail == nil }
    }

    var draftsReady: [Lead] {
        vm.leads.filter { $0.draftedEmail != nil && $0.draftedEmail?.sentDate == nil }
    }

    var followUpDraftsReady: [Lead] {
        vm.leads.filter { $0.followUpEmail != nil && $0.followUpEmail?.sentDate == nil }
    }

    @State private var selectedLead: Lead?
    @State private var showingEditSheet = false
    @State private var showingSendConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var editSubject = ""
    @State private var emailBody = ""
    @State private var showingFollowUpEditSheet = false
    @State private var showingFollowUpSendConfirmation = false
    @State private var showingFollowUpDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Sub-header: actions
            HStack {
                if vm.isLoading {
                    HStack {
                        ProgressView()
                        Text("\(vm.currentStep)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Alle Emails generieren") {
                    Task { await vm.draftAllEmails() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftsNeeded.isEmpty || vm.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if !vm.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(vm.errorMessage).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("X") { vm.errorMessage = "" }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            if draftsReady.isEmpty && draftsNeeded.isEmpty && followUpDraftsReady.isEmpty {
                EmailDraftEmptyView()
            } else {
                List {
                    if !draftsNeeded.isEmpty {
                        Section("Email noch zu erstellen (\(draftsNeeded.count))") {
                            ForEach(draftsNeeded, id: \.id) { lead in
                                EmailDraftNeededRow(lead: lead, vm: vm)
                            }
                        }
                    }
                    if !draftsReady.isEmpty {
                        Section("Fertige Drafts (\(draftsReady.count))") {
                            ForEach(draftsReady, id: \.id) { lead in
                                EmailDraftReadyRow(
                                    lead: lead,
                                    onEdit: {
                                        selectedLead = lead
                                        if let draft = lead.draftedEmail {
                                            editSubject = draft.subject
                                            emailBody = draft.body
                                        }
                                        showingEditSheet = true
                                    },
                                    onSend: {
                                        selectedLead = lead
                                        showingSendConfirmation = true
                                    },
                                    onDelete: {
                                        selectedLead = lead
                                        showingDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                    if !followUpDraftsReady.isEmpty {
                        Section("Follow-Up Drafts (\(followUpDraftsReady.count))") {
                            ForEach(followUpDraftsReady, id: \.id) { lead in
                                FollowUpDraftReadyRow(
                                    lead: lead,
                                    onEdit: {
                                        selectedLead = lead
                                        if let fu = lead.followUpEmail {
                                            editSubject = fu.subject
                                            emailBody = fu.body
                                        }
                                        showingFollowUpEditSheet = true
                                    },
                                    onSend: {
                                        selectedLead = lead
                                        showingFollowUpSendConfirmation = true
                                    },
                                    onDelete: {
                                        selectedLead = lead
                                        showingFollowUpDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        // Original Email Sheet + Alerts
        .sheet(isPresented: $showingEditSheet) {
            if let lead = selectedLead {
                EditDraftSheet(
                    lead: lead,
                    subject: $editSubject,
                    emailBody: $emailBody,
                    onSave: { newSubject, newBody in
                        vm.updateDraft(for: lead, subject: newSubject, body: newBody)
                        showingEditSheet = false
                    },
                    onCancel: { showingEditSheet = false }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        .alert("Email senden?", isPresented: $showingSendConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") {
                if let lead = selectedLead {
                    Task { await vm.sendEmail(to: lead) }
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll die Email an \(lead.name) (\(lead.email)) gesendet werden?")
            }
        }
        .alert("Draft loeschen?", isPresented: $showingDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loeschen", role: .destructive) {
                if let lead = selectedLead { vm.deleteDraft(for: lead) }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll der Email-Draft fuer \(lead.name) geloescht werden?")
            }
        }
        // Follow-Up Sheet + Alerts
        .sheet(isPresented: $showingFollowUpEditSheet) {
            if let lead = selectedLead {
                EditDraftSheet(
                    lead: lead,
                    subject: $editSubject,
                    emailBody: $emailBody,
                    titleLabel: "Follow-Up bearbeiten",
                    onSave: { newSubject, newBody in
                        vm.updateFollowUpDraft(for: lead, subject: newSubject, body: newBody)
                        showingFollowUpEditSheet = false
                    },
                    onCancel: { showingFollowUpEditSheet = false }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        .alert("Follow-Up senden?", isPresented: $showingFollowUpSendConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") {
                if let lead = selectedLead {
                    vm.approveFollowUp(for: lead.id)
                    Task { await vm.sendFollowUp(for: lead.id) }
                }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll das Follow-Up an \(lead.name) (\(lead.email)) gesendet werden?")
            }
        }
        .alert("Follow-Up Draft loeschen?", isPresented: $showingFollowUpDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Loeschen", role: .destructive) {
                if let lead = selectedLead { vm.deleteFollowUpDraft(for: lead) }
            }
        } message: {
            if let lead = selectedLead {
                Text("Soll der Follow-Up Draft fuer \(lead.name) geloescht werden?")
            }
        }
    }
}

// MARK: - Outbox Content (extracted from OutboxView)
struct OutboxContent: View {
    @ObservedObject var vm: AppViewModel

    var approvedEmails: [Lead] {
        vm.leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }
    }

    var sentEmails: [Lead] {
        vm.leads.filter { $0.dateEmailSent != nil }
            .sorted { ($0.dateEmailSent ?? .distantPast) > ($1.dateEmailSent ?? .distantPast) }
    }

    func repliesForLead(_ lead: Lead) -> [GmailService.GmailMessage] {
        guard let subject = lead.draftedEmail?.subject ?? lead.followUpEmail?.subject else { return [] }
        let cleanSubject = subject.lowercased()
            .replacingOccurrences(of: "re: ", with: "")
            .replacingOccurrences(of: "aw: ", with: "")
        return vm.replies.filter { reply in
            let replySubj = reply.subject.lowercased()
                .replacingOccurrences(of: "re: ", with: "")
                .replacingOccurrences(of: "aw: ", with: "")
            return replySubj.contains(cleanSubject) || cleanSubject.contains(replySubj)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pipeline action buttons
            HStack(spacing: 12) {
                VStack(alignment: .trailing) {
                    Text("\(approvedEmails.count) bereit zum Senden")
                        .foregroundStyle(.secondary)
                    Text("\(sentEmails.count) gesendet")
                        .foregroundStyle(.green)
                    if !vm.replies.isEmpty {
                        Text("\(vm.replies.count) Antworten")
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                Button(action: { vm.approveAllEmails() }) {
                    Label("Alle freigeben", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isLoading)

                Button(action: { Task { await vm.sendAllApproved() } }) {
                    Label("Alle senden", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading || approvedEmails.isEmpty)

                Button(action: { Task { await vm.checkForReplies() } }) {
                    Label("Antworten pruefen", systemImage: "envelope.open.fill")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if vm.isLoading {
                HStack {
                    ProgressView()
                    Text(vm.currentStep).font(.caption)
                }
                .padding(.horizontal, 24)
            }

            Divider()

            if approvedEmails.isEmpty && sentEmails.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Keine Emails zum Versenden.")
                    Text("Gebe Emails im Draft-Tab frei.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    if !approvedEmails.isEmpty {
                        Section(header: Text("Bereit zum Senden (\(approvedEmails.count))")) {
                            ForEach(approvedEmails) { lead in
                                OutboxCard(lead: lead, vm: vm, isSent: false, matchedReplies: [])
                            }
                        }
                    }
                    if !sentEmails.isEmpty {
                        Section(header: Text("Gesendet (\(sentEmails.count))")) {
                            ForEach(sentEmails) { lead in
                                OutboxCard(lead: lead, vm: vm, isSent: true,
                                           matchedReplies: repliesForLead(lead))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Inbox Content (extracted from InboxFollowUpView)
struct InboxContent: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedInboxTab = 0
    @State private var hasCheckedReplies = false

    private var unsubscribeCount: Int {
        vm.replies.filter { reply in
            let body = reply.body.lowercased()
            let subject = reply.subject.lowercased()
            return body.contains("unsubscribe") || body.contains("abmelden") ||
                   body.contains("austragen") || body.contains("remove me") ||
                   subject.contains("unsubscribe") || subject.contains("abmelden")
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if unsubscribeCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("\(unsubscribeCount) Unsubscribe")
                            .font(.caption).bold().foregroundStyle(.red)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            Picker("", selection: $selectedInboxTab) {
                Text("Replies (\(vm.replies.count))").tag(0)
                Text("Follow-Up needed (\(vm.checkFollowUpsNeeded().count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Divider()

            if selectedInboxTab == 0 {
                inboxRepliesView
            } else {
                inboxFollowUpView
            }
        }
        .task {
            if !hasCheckedReplies {
                let sentCount = vm.leads.filter {
                    $0.dateEmailSent != nil || $0.dateFollowUpSent != nil
                }.count
                if sentCount > 0 {
                    await vm.checkForReplies()
                    hasCheckedReplies = true
                }
            }
        }
    }

    private var inboxRepliesView: some View {
        VStack(spacing: 0) {
            HStack {
                if unsubscribeCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                        Text("\(unsubscribeCount) unsubscribe request(s) — mark as Do Not Contact")
                            .font(.caption).foregroundStyle(.red)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                    Spacer()
                } else {
                    Spacer()
                }
                Button("Check inbox") {
                    Task {
                        await vm.checkForReplies()
                        hasCheckedReplies = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading)
            }
            .padding(16)

            if vm.isLoading {
                ProgressView(vm.currentStep).padding()
            }

            if vm.replies.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "tray.fill")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No replies found.")
                        .foregroundStyle(.secondary)
                    if !hasCheckedReplies {
                        Text("Inbox will be checked automatically...")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            } else {
                List {
                    ForEach(vm.replies) { reply in
                        ReplyCard(reply: reply, vm: vm)
                    }
                }
            }
        }
    }

    private var inboxFollowUpView: some View {
        VStack(spacing: 0) {
            let needsFollowUp = vm.checkFollowUpsNeeded()
            if needsFollowUp.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock.fill")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No follow-ups needed.")
                        .foregroundStyle(.secondary)
                    Text("Follow-ups are suggested 14 days after first send.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(needsFollowUp) { lead in
                        FollowUpCard(lead: lead, vm: vm)
                    }
                }
            }
        }
    }
}
