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
                    $0.status == .emailSent || $0.status == .followUpSent
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
                        ReplyCard(reply: reply)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.blue)
                Text(reply.from).font(.headline)
                Spacer()
                Text(reply.date).font(.caption).foregroundStyle(.secondary)
            }
            Text(reply.subject).font(.subheadline).foregroundStyle(.secondary)
            Text(reply.snippet)
                .font(.caption).foregroundStyle(.tertiary)
                .lineLimit(3)
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
