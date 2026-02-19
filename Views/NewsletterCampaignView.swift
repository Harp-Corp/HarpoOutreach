import SwiftUI

struct NewsletterCampaignView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingSendConfirmation = false
    @State private var selectedCampaignIndex: Int?
    @State private var isSending = false
    
    var body: some View {
        NavigationView {
            List {
                // Campaign Stats Overview
                Section("Overview") {
                    HStack(spacing: 20) {
                        StatCard(title: "Campaigns", value: "\(viewModel.campaigns.count)", icon: "envelope.fill", color: .blue)
                        StatCard(title: "Social Posts", value: "\(viewModel.socialPosts.count)", icon: "megaphone.fill", color: .purple)
                        StatCard(title: "Total Sent", value: "\(viewModel.campaigns.reduce(0) { $0 + $1.sentCount })", icon: "paperplane.fill", color: .green)
                    }
                    .padding(.vertical, 4)
                }
                
                // Active Campaigns
                Section("Newsletter Campaigns") {
                    if viewModel.campaigns.isEmpty {
                        ContentUnavailableView(
                            "No Campaigns",
                            systemImage: "envelope.badge",
                            description: Text("Generate content in Content Studio to create campaigns")
                        )
                    } else {
                        ForEach(Array(viewModel.campaigns.enumerated()), id: \.element.id) { index, campaign in
                            CampaignRow(campaign: campaign)
                                .contextMenu {
                                    if campaign.status == .draft {
                                        Button("Send Campaign") {
                                            selectedCampaignIndex = index
                                            showingSendConfirmation = true
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        viewModel.campaigns.remove(at: index)
                                    }
                                }
                        }
                    }
                }
                
                // Social Posts
                Section("Social Posts") {
                    if viewModel.socialPosts.isEmpty {
                        ContentUnavailableView(
                            "No Posts",
                            systemImage: "megaphone",
                            description: Text("Generate social posts in Content Studio")
                        )
                    } else {
                        ForEach(viewModel.socialPosts) { post in
                            SocialPostRow(post: post)
                        }
                    }
                }
            }
            .navigationTitle("Campaigns")
            .alert("Send Campaign?", isPresented: $showingSendConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Send") { sendCampaign() }
            } message: {
                if let idx = selectedCampaignIndex, idx < viewModel.campaigns.count {
                    let recipients = viewModel.newsletterService.buildRecipientList(
                        from: viewModel.leads,
                        industries: viewModel.campaigns[idx].targetIndustries,
                        regions: viewModel.campaigns[idx].targetRegions
                    )
                    Text("Send \"\(viewModel.campaigns[idx].subject)\" to \(recipients.count) recipients?")
                }
            }
            .overlay {
                if isSending {
                    ZStack {
                        Color.black.opacity(0.3)
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Sending newsletter...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                }
            }
        }
    }
    
    private func sendCampaign() {
        guard let index = selectedCampaignIndex, index < viewModel.campaigns.count else { return }
        isSending = true
        Task {
            await viewModel.sendNewsletterCampaign(at: index)
            await MainActor.run { isSending = false }
        }
    }
}

// MARK: - Campaign Row
struct CampaignRow: View {
    let campaign: NewsletterCampaign
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(campaign.name)
                    .font(.headline)
                Spacer()
                StatusBadge(status: campaign.status)
            }
            Text(campaign.subject)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 16) {
                Label("\(campaign.recipientCount)", systemImage: "person.2")
                Label("\(campaign.sentCount)", systemImage: "paperplane")
                Label("\(campaign.openCount)", systemImage: "eye")
                Label("\(campaign.clickCount)", systemImage: "hand.tap")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: CampaignStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(6)
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
                Image(systemName: post.platform == .linkedIn ? "link" : "bird")
                    .foregroundColor(post.platform == .linkedIn ? .blue : .cyan)
                Text(post.platform.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(post.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(post.status == .published ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }
            Text(String(post.content.prefix(120)) + (post.content.count > 120 ? "..." : ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !post.hashtags.isEmpty {
                Text(post.hashtags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
