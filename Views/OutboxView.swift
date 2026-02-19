import SwiftUI

struct OutboxView: View {
    @ObservedObject var vm: AppViewModel

    var approvedEmails: [Lead] {
        vm.leads.filter {
            $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil
        }
    }

    var sentEmails: [Lead] {
        vm.leads.filter {
            $0.dateEmailSent != nil
        }.sorted {
            ($0.dateEmailSent ?? .distantPast) > ($1.dateEmailSent ?? .distantPast)
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
                }
            }
            .padding(24)

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
                                OutboxCard(lead: lead, vm: vm, isSent: false)
                            }
                        }
                    }

                    if !sentEmails.isEmpty {
                        Section(header: Text("Gesendet (\(sentEmails.count))")) {
                            ForEach(sentEmails) { lead in
                                OutboxCard(lead: lead, vm: vm, isSent: true)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
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
                            Text(sentDate, style: .time)
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
            }

            if let email = lead.draftedEmail {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Betreff: \(email.subject)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(email.body.prefix(150) + (email.body.count > 150 ? "..." : ""))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
            }

            if isSent {
                HStack(spacing: 8) {
                    Label(lead.status.rawValue, systemImage: "envelope.fill")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                    if !lead.replyReceived.isEmpty {
                        Label("Antwort erhalten", systemImage: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
