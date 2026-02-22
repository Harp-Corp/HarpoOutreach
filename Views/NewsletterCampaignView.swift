import SwiftUI

struct NewsletterCampaignView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingSendConfirmation = false
    @State private var selectedCampaignIndex: Int?
    @State private var isSending = false
    @State private var editingCampaignIndex: Int?
    @State private var editSubject = ""
    @State private var editBody = ""
    @State private var showContactPicker = false
    @State private var selectedLeadIDs: Set<UUID> = []
    @State private var publishingPostIndex: Int?
    @State private var showPublishError = false
    @State private var publishError = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Kampagnen")
                        .font(.largeTitle).bold()
                    Text("Newsletter und LinkedIn Posts verwalten")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()

            List {
                // Stats
                Section("Uebersicht") {
                    HStack(spacing: 20) {
                        StatCard(title: "Kampagnen", value: "\(viewModel.campaigns.count)", icon: "envelope.fill", color: .blue)
                        StatCard(title: "LinkedIn", value: "\(viewModel.socialPosts.count)", icon: "link", color: .purple)
                        StatCard(title: "Gesendet", value: "\(viewModel.campaigns.reduce(0) { $0 + $1.sentCount })", icon: "paperplane.fill", color: .green)
                    }.padding(.vertical, 4)
                }

                // Campaigns
                Section("Newsletter Kampagnen") {
                    if viewModel.campaigns.isEmpty {
                        ContentUnavailableView("Keine Kampagnen", systemImage: "envelope.badge", description: Text("Erstelle Inhalte im Content Studio"))
                    } else {
                        ForEach(Array(viewModel.campaigns.enumerated()), id: \.element.id) { index, campaign in
                            CampaignRow(campaign: campaign)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if campaign.status == .draft {
                                        editSubject = campaign.subject
                                        editBody = campaign.htmlBody
                                        editingCampaignIndex = index
                                    }
                                }
                                .contextMenu {
                                    if campaign.status == .draft {
                                        Button("Bearbeiten") {
                                            editSubject = campaign.subject
                                            editBody = campaign.htmlBody
                                            editingCampaignIndex = index
                                        }
                                        Button("Empfaenger waehlen & Senden") {
                                            selectedCampaignIndex = index
                                            selectedLeadIDs = Set(verifiedLeads.map { $0.id })
                                            showContactPicker = true
                                        }
                                    }
                                    Button("Loeschen", role: .destructive) {
                                        viewModel.campaigns.remove(at: index)
                                    }
                                }
                        }
                    }
                }

                // LinkedIn Posts
                Section("LinkedIn Posts") {
                    if viewModel.socialPosts.isEmpty {
                        ContentUnavailableView("Keine Posts", systemImage: "link", description: Text("Erstelle Posts im Content Studio"))
                    } else {
                        ForEach(Array(viewModel.socialPosts.enumerated()), id: \.element.id) { index, post in
                            SocialPostRow(post: post)
                                .contextMenu {
                                    if post.status == .draft {
                                        Button("Auf LinkedIn posten") {
                                            publishLinkedInPost(at: index)
                                        }
                                    }
                                    Button("Loeschen", role: .destructive) {
                                        viewModel.socialPosts.remove(at: index)
                                    }
                                }
                        }
                    }
                }
            }
        }
        // Edit Campaign Sheet
        .sheet(item: editingBinding) { idx in
            campaignEditSheet(index: idx)
        }
        // Contact Picker Sheet
        .sheet(isPresented: $showContactPicker) {
            contactPickerSheet
        }
        .alert("LinkedIn Fehler", isPresented: $showPublishError) {
            Button("OK") { }
        } message: {
            Text(publishError)
        }
        .overlay {
            if isSending {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5)
                        Text("Sende Newsletter...").font(.headline).foregroundColor(.white)
                    }.padding(30).background(.ultraThinMaterial).cornerRadius(16)
                }
            }
        }
    }

    // MARK: - Verified Leads
    private var verifiedLeads: [Lead] {
        viewModel.leads.filter { $0.emailVerified && !$0.email.isEmpty && !$0.unsubscribed && $0.status != .doNotContact }
    }

    // MARK: - Edit Binding Helper
    private var editingBinding: Binding<IntWrapper?> {
        Binding<IntWrapper?>(
            get: { editingCampaignIndex.map { IntWrapper(value: $0) } },
            set: { editingCampaignIndex = $0?.value }
        )
    }

    // MARK: - Campaign Edit Sheet
    private func campaignEditSheet(index: IntWrapper) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kampagne bearbeiten").font(.headline)
                Spacer()
                Button("Abbrechen") { editingCampaignIndex = nil }.buttonStyle(.bordered)
                Button("Speichern") {
                    if index.value < viewModel.campaigns.count {
                        viewModel.campaigns[index.value].subject = editSubject
                        viewModel.campaigns[index.value].htmlBody = editBody
                    }
                    editingCampaignIndex = nil
                }.buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                Section("Betreff") {
                    TextField("Betreff", text: $editSubject)
                }
                Section("Inhalt") {
                    TextEditor(text: $editBody)
                        .frame(minHeight: 300)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }.frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Contact Picker Sheet
    private var contactPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Empfaenger waehlen").font(.headline)
                Spacer()
                Text("\(selectedLeadIDs.count) ausgewaehlt").foregroundStyle(.secondary)
                Button("Abbrechen") { showContactPicker = false }.buttonStyle(.bordered)
                Button("Senden") {
                    showContactPicker = false
                    sendCampaignToSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLeadIDs.isEmpty)
            }.padding()
            Divider()
            List {
                Section {
                    Button("Alle auswaehlen") {
                        selectedLeadIDs = Set(verifiedLeads.map { $0.id })
                    }
                    Button("Keine auswaehlen") {
                        selectedLeadIDs.removeAll()
                    }
                }
                Section("Verifizierte Kontakte (\(verifiedLeads.count))") {
                    ForEach(verifiedLeads) { lead in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedLeadIDs.contains(lead.id) },
                                set: { isOn in
                                    if isOn { selectedLeadIDs.insert(lead.id) }
                                    else { selectedLeadIDs.remove(lead.id) }
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(lead.name).font(.body)
                                    Text("\(lead.email) - \(lead.company)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }.frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Actions
    private func sendCampaignToSelected() {
        guard let index = selectedCampaignIndex, index < viewModel.campaigns.count else { return }
        isSending = true
        Task {
            await viewModel.sendNewsletterCampaign(at: index)
            await MainActor.run { isSending = false }
        }
    }

    private func publishLinkedInPost(at index: Int) {
        guard index < viewModel.socialPosts.count else { return }
        guard viewModel.linkedInAuthService.isAuthenticated else {
            publishError = "Nicht bei LinkedIn angemeldet. Bitte in Einstellungen verbinden."
            showPublishError = true
            return
        }
        let post = viewModel.socialPosts[index]
        Task {
            do {
                let accessToken = try await viewModel.linkedInAuthService.getAccessToken()
                        let postURL = try await viewModel.socialPostService.postToLinkedIn(
                            post: post,
                            accessToken: accessToken,
                            personId: viewModel.linkedInAuthService.getPersonId() ?? ""
                        )
                        var updated = post
                        updated.postURL = postURL
                        updated.status = .published
                        updated.publishedDate = Date()
                await MainActor.run {
                    viewModel.socialPosts[index] = updated
                }
            } catch {
                await MainActor.run {
                    publishError = error.localizedDescription
                    showPublishError = true
                }
            }
        }
    }
}

// MARK: - IntWrapper for sheet binding
struct IntWrapper: Identifiable {
    let id = UUID()
    let value: Int
}

// MARK: - Campaign Row
struct CampaignRow: View {
    let campaign: NewsletterCampaign
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(campaign.name).font(.headline)
                Spacer()
                StatusBadge(status: campaign.status)
            }
            Text(campaign.subject).font(.subheadline).foregroundColor(.secondary)
            HStack(spacing: 16) {
                Label("\(campaign.recipientCount)", systemImage: "person.2")
                Label("\(campaign.sentCount)", systemImage: "paperplane")
            }.font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: CampaignStatus
    var body: some View {
        Text(status.rawValue)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor).cornerRadius(6)
    }
    private var statusColor: Color {
        switch status {
        case .draft: return .gray
        case .scheduled: return .orange
        case .sending: return .blue
        case .sent: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Social Post Row
struct SocialPostRow: View {
    let post: SocialPost
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "link").foregroundColor(.blue)
                Text("LinkedIn").font(.caption).fontWeight(.medium)
                Spacer()
                Text(post.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(post.status == .published ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }
            Text(String(post.content.prefix(120)) + (post.content.count > 120 ? "..." : ""))
                .font(.subheadline).foregroundColor(.secondary)
            if !post.hashtags.isEmpty {
                Text(post.hashtags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2).foregroundColor(.blue)
            }
        }.padding(.vertical, 4)
    }
}
