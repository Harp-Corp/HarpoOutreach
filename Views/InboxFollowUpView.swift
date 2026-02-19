import SwiftUI

struct InboxFollowUpView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedTab = 0
    @State private var hasCheckedReplies = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inbox & Follow-Up").font(.largeTitle).bold()
                Spacer()
            }
            .padding(24)

            Picker("", selection: $selectedTab) {
                Text("Antworten (\(vm.replies.count))").tag(0)
                Text("Follow-Up noetig (\(vm.checkFollowUpsNeeded().count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Divider()

            if selectedTab == 0 {
                repliesView
            } else {
                followUpView
            }
        }
        .task {
            // Automatisch Antworten pruefen beim Oeffnen des Tabs
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

    var repliesView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Posteingang pruefen") {
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
                    Text("Keine Antworten gefunden.")
                        .foregroundStyle(.secondary)
                    if !hasCheckedReplies {
                        Text("Posteingang wird automatisch geprueft...")
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

    var followUpView: some View {
        VStack(spacing: 0) {
            let needsFollowUp = vm.checkFollowUpsNeeded()

            if needsFollowUp.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock.fill")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Keine Follow-Ups noetig.")
                        .foregroundStyle(.secondary)
                    Text("Follow-Ups werden 14 Tage nach Erstversand vorgeschlagen.")
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

struct ReplyCard: View {
    let reply: GmailService.GmailMessage
    @ObservedObject var vm: AppViewModel
    @State private var isExpanded = false

    // Finde den passenden Lead fuer diesen Reply
    private var matchedLead: Lead? {
        let fromEmail = reply.from.lowercased()
        return vm.leads.first { fromEmail.contains($0.email.lowercased()) && !$0.email.isEmpty }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Kontakt-Info falls gefunden
                if let lead = matchedLead {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lead.name).font(.callout).bold()
                            Text(lead.company).font(.caption).foregroundStyle(.secondary)
                            Text(lead.title).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        // Status Badge
                        Text(lead.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                    Divider()
                }

                // Gesendete Original-Email (falls vorhanden)
                if let lead = matchedLead, let sentEmail = lead.draftedEmail {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(.blue)
                                Text("Gesendete Email")
                                    .font(.caption).bold()
                                    .foregroundStyle(.blue)
                                Spacer()
                                if let sentDate = lead.dateEmailSent {
                                    Text(sentDate, style: .date)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text("Betreff: \(sentEmail.subject)")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                Text(sentEmail.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 150)
                        }
                        .padding(4)
                    }
                }

                // Follow-Up Email (falls vorhanden)
                if let lead = matchedLead, let followUp = lead.followUpEmail, lead.dateFollowUpSent != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "arrow.uturn.forward")
                                    .foregroundStyle(.purple)
                                Text("Follow-Up")
                                    .font(.caption).bold()
                                    .foregroundStyle(.purple)
                                Spacer()
                                if let sentDate = lead.dateFollowUpSent {
                                    Text(sentDate, style: .date)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text("Betreff: \(followUp.subject)")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                Text(followUp.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 150)
                        }
                        .padding(4)
                    }
                }

                // Empfangene Antwort (vollstaendig)
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundStyle(.green)
                            Text("Antwort")
                                .font(.caption).bold()
                                .foregroundStyle(.green)
                            Spacer()
                            Text(reply.date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Betreff: \(reply.subject)")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ScrollView {
                            Text(reply.body)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                    }
                    .padding(4)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reply.from).font(.headline)
                    Text(reply.subject).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reply.date).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FollowUpCard: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.name).font(.headline)
                    Text(lead.company).font(.subheadline).foregroundStyle(.secondary)
                    Text(lead.email).font(.caption).foregroundStyle(.blue)
                }
                Spacer()
                if let sentDate = lead.dateEmailSent {
                    VStack(alignment: .trailing) {
                        let days = Calendar.current.dateComponents([.day], from: sentDate, to: Date()).day ?? 0
                        Text("\(days) Tage seit Versand")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 8) {
                if lead.followUpEmail == nil {
                    Button("Follow-Up erstellen") {
                        Task { await vm.draftFollowUp(for: lead.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if lead.followUpEmail?.isApproved == false {
                    Button("Follow-Up freigeben") {
                        vm.approveFollowUp(for: lead.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Follow-Up senden") {
                        Task { await vm.sendFollowUp(for: lead.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
