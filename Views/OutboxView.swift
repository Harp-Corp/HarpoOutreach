import SwiftUI

struct OutboxView: View {
    @ObservedObject var vm: AppViewModel

    var approvedEmails: [Lead] {
        vm.leads.filter { $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil }
    }

    var sentEmails: [Lead] {
        vm.leads.filter { $0.dateEmailSent != nil }
            .sorted { ($0.dateEmailSent ?? .distantPast) > ($1.dateEmailSent ?? .distantPast) }
    }

    // Replies die per Subject zu gesendeten Mails passen
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
            HStack {
                VStack(alignment: .leading) {
                    Text("Outbox").font(.largeTitle).bold()
                    Text("Freigegebene Emails versenden")
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
            }
            .padding(24)
            
            // Pipeline Buttons
            HStack(spacing: 12) {
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

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

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

struct OutboxCard: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel
    var isSent: Bool = false
    var matchedReplies: [GmailService.GmailMessage] = []
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Gesendete Email
                if let email = lead.draftedEmail {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(.blue)
                                Text("Gesendete Email").font(.caption).bold()
                                    .foregroundStyle(.blue)
                                Spacer()
                                if let d = lead.dateEmailSent {
                                    Text(d, style: .date).font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Betreff: \(email.subject)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(email.body.prefix(200) + (email.body.count > 200 ? "..." : ""))
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(4)
                        }.padding(4)
                    }
                }

                // Follow-Up (falls gesendet)
                if let followUp = lead.followUpEmail, lead.dateFollowUpSent != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "arrow.uturn.forward")
                                    .foregroundStyle(.purple)
                                Text("Follow-Up").font(.caption).bold()
                                    .foregroundStyle(.purple)
                                Spacer()
                                if let d = lead.dateFollowUpSent {
                                    Text(d, style: .date).font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Betreff: \(followUp.subject)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(followUp.body.prefix(150) + (followUp.body.count > 150 ? "..." : ""))
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(3)
                        }.padding(4)
                    }
                }

                // Antworten (Subject-basiert, unabhaengig vom Sender)
                if !matchedReplies.isEmpty {
                    ForEach(matchedReplies) { reply in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "arrowshape.turn.up.left.fill")
                                        .foregroundStyle(.green)
                                    Text("Antwort von: \(reply.from)").font(.caption).bold()
                                        .foregroundStyle(.green)
                                    Spacer()
                                    Text(reply.date).font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Betreff: \(reply.subject)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                                Text(reply.body.prefix(300) + (reply.body.count > 300 ? "..." : ""))
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .lineLimit(6)
                            }.padding(4)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.name).font(.headline)
                    Text(lead.company).font(.subheadline).foregroundStyle(.secondary)
                    Text(lead.email).font(.caption).foregroundStyle(.blue)
                }
                Spacer()
                if isSent {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let sentDate = lead.dateEmailSent {
                            Text(sentDate, style: .date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("Senden") {
                        Task { await vm.sendEmail(for: lead.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if !matchedReplies.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                        Text("\(matchedReplies.count)")
                            .font(.caption2).bold()
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
