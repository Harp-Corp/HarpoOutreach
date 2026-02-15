import SwiftUI

struct InboxFollowUpView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedTab = 0

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
    }

    var repliesView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Posteingang pruefen") {
                    Task { await vm.checkForReplies() }
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
                    Spacer()
                }
            } else {
                List {
                    ForEach(vm.replies) { reply in
                        ReplyCard(reply: reply)
                    }
                }
            }
        }
    }

    var followUpView: some View {
        VStack(spacing: 0) {
            let needed = vm.checkFollowUpsNeeded()

            if needed.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48)).foregroundStyle(.green)
                    Text("Keine Follow-Ups noetig.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(needed) { lead in
                        FollowUpCard(lead: lead, vm: vm)
                    }
                }
            }
        }
    }
}

struct ReplyCard: View {
    let reply: GmailService.GmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "envelope.open.fill")
                    .foregroundStyle(.green)
                Text(reply.from).font(.headline)
                Spacer()
                Text(reply.date).font(.caption).foregroundStyle(.secondary)
            }
            Text(reply.subject).font(.subheadline).bold()
            Text(reply.snippet).font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                Text(reply.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
}

struct FollowUpCard: View {
    let lead: Lead
    @ObservedObject var vm: AppViewModel
    @State private var showDraft = false

    var daysSinceEmail: Int {
        guard let sent = lead.dateEmailSent else { return 0 }
        return Calendar.current.dateComponents([.day], from: sent, to: Date()).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(lead.name).font(.headline)
                    Text(lead.company.name).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(daysSinceEmail) Tage seit erster Email").font(.caption)
                }
                Spacer()
                if lead.followUpEmail == nil {
                    Button("Follow-Up erstellen") {
                        Task {
                            await vm.draftFollowUp(for: lead.id)
                            showDraft = true
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                } else if lead.followUpEmail?.isApproved != true {
                    Button("Freigeben") {
                        vm.approveFollowUp(for: lead.id)
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        Task { await vm.sendFollowUp(for: lead.id) }
                    } label: {
                        Label("Senden", systemImage: "paperplane.fill")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }

            if showDraft || lead.followUpEmail != nil {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Betreff:").font(.caption).foregroundStyle(.secondary)
                    Text(lead.followUpEmail?.subject ?? "").font(.body)
                    Text("Email:").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(lead.followUpEmail?.body ?? "")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(6)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
}
