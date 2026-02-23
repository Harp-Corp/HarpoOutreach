import SwiftUI

struct InboxFollowUpView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedTab = 0
    @State private var hasCheckedReplies = false

    // Compute unsubscribe count from all replies
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
                Text("Inbox & Follow-Up").font(.largeTitle).bold()
                Spacer()
                // Show unsubscribe warning badge if any
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
            }
            .padding(24)

            Picker("", selection: $selectedTab) {
                Text("Replies (\(vm.replies.count))").tag(0)
                Text("Follow-Up needed (\(vm.checkFollowUpsNeeded().count))").tag(1)
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
            // Automatically check replies when tab is opened
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

    var followUpView: some View {
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

struct ReplyCard: View {
    let reply: GmailService.GmailMessage
    @ObservedObject var vm: AppViewModel
    @State private var isExpanded = false

    // Determine if this reply is an unsubscribe request
    private var isUnsubscribe: Bool {
        let body = reply.body.lowercased()
        let subject = reply.subject.lowercased()
        return body.contains("unsubscribe") || body.contains("abmelden") ||
               body.contains("austragen") || body.contains("remove me") ||
               subject.contains("unsubscribe") || subject.contains("abmelden")
    }

    // Find the matching lead for this reply
    private var matchedLead: Lead? {
        let fromEmail = reply.from.lowercased()
        return vm.leads.first { fromEmail.contains($0.email.lowercased()) && !$0.email.isEmpty }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // UNSUBSCRIBE BANNER
                if isUnsubscribe {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.white)
                        Text("UNSUBSCRIBE REQUEST — Do Not Contact")
                            .font(.caption).bold().foregroundStyle(.white)
                        Spacer()
                        if let lead = matchedLead, lead.status != .doNotContact {
                            Button("Mark Do Not Contact") {
                                var updated = lead
                                updated.status = .doNotContact
                                vm.updateLead(updated)
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.white)
                            .controlSize(.small)
                        } else if matchedLead?.status == .doNotContact {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                                Text("Marked").font(.caption2).foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }

                // Contact info if found
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
                            .background(isUnsubscribe ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                            .foregroundStyle(isUnsubscribe ? .red : .green)
                            .cornerRadius(4)
                    }
                    Divider()
                }

                // Sent original email (if available)
                if let lead = matchedLead, let sentEmail = lead.draftedEmail {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "paperplane.fill").foregroundStyle(.blue)
                                Text("Sent Email").font(.caption).bold().foregroundStyle(.blue)
                                Spacer()
                                if let sentDate = lead.dateEmailSent {
                                    Text(sentDate, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text("Subject: \(sentEmail.subject)").font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                Text(sentEmail.body)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }.frame(maxHeight: 150)
                        }.padding(4)
                    }
                }

                // Follow-Up email (if sent)
                if let lead = matchedLead, let followUp = lead.followUpEmail, lead.dateFollowUpSent != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "arrow.uturn.forward").foregroundStyle(.purple)
                                Text("Follow-Up").font(.caption).bold().foregroundStyle(.purple)
                                Spacer()
                                if let sentDate = lead.dateFollowUpSent {
                                    Text(sentDate, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text("Subject: \(followUp.subject)").font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                Text(followUp.body)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }.frame(maxHeight: 150)
                        }.padding(4)
                    }
                }

                // Full received reply
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundStyle(isUnsubscribe ? .red : .green)
                            Text("Reply").font(.caption).bold()
                                .foregroundStyle(isUnsubscribe ? .red : .green)
                            Spacer()
                            Text(reply.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Subject: \(reply.subject)").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ScrollView {
                            Text(reply.body)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }.frame(maxHeight: 300)
                    }.padding(4)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 8) {
                // Unsubscribe: red icon, normal reply: green
                Image(systemName: isUnsubscribe ? "exclamationmark.octagon.fill" : "arrowshape.turn.up.left.fill")
                    .foregroundStyle(isUnsubscribe ? .red : .green)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reply.from).font(.headline)
                        if isUnsubscribe {
                            Text("UNSUBSCRIBE")
                                .font(.caption2).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }
                    Text(reply.subject).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reply.date).font(.caption).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(isUnsubscribe ? Color.red.opacity(0.06) : Color.clear)
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
                        Text("\(days) days since send")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack(spacing: 8) {
                if lead.followUpEmail == nil {
                    Button("Create Follow-Up") {
                        Task { await vm.draftFollowUp(for: lead.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if lead.followUpEmail?.isApproved == false {
                    Button("Approve Follow-Up") {
                        vm.approveFollowUp(for: lead.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Send Follow-Up") {
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
