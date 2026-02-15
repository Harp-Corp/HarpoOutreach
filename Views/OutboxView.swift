import SwiftUI

struct OutboxView: View {
    @ObservedObject var vm: AppViewModel

    var approvedEmails: [Lead] {
        vm.leads.filter {
            $0.draftedEmail?.isApproved == true && $0.dateEmailSent == nil
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
                Text("\(approvedEmails.count) bereit zum Senden")
                    .foregroundStyle(.secondary)
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

            if approvedEmails.isEmpty {
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
                    ForEach(approvedEmails) { lead in
                        OutboxCard(lead: lead, vm: vm)
                    }
                }
            }
        }
    }
}

struct OutboxCard: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(lead.name).font(.headline)
                    Text(lead.company.name).font(.subheadline).foregroundStyle(.secondary)
                    Text("An: \(lead.email)").font(.caption)
                }
                Spacer()
                Button {
                    Task { await vm.sendEmail(for: lead.id) }
                } label: {
                    Label("Senden", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Betreff:").font(.caption).foregroundStyle(.secondary)
                Text(lead.draftedEmail?.subject ?? "").font(.body)
                Text("Vorschau:").font(.caption).foregroundStyle(.secondary)
                Text(String((lead.draftedEmail?.body ?? "").prefix(200)) + "...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}
