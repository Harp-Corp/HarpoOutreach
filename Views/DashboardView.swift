import SwiftUI

// MARK: - Main Dashboard
struct DashboardView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showQuickCampaign = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DashboardHeaderView(vm: vm, showQuickCampaign: $showQuickCampaign)
                DashboardStatusBanner(vm: vm)
                DashboardKPIGrid(vm: vm)
                DashboardCampaignView(vm: vm)
                DashboardSocialPostsView(vm: vm)
                DashboardPipelineView(vm: vm)
                DashboardRecentView(leads: vm.leads)
            }
            .padding(24)
        }
        .sheet(isPresented: $showQuickCampaign) {
            QuickCampaignView(vm: vm)
        }
    }
}

// MARK: - Header
struct DashboardHeaderView: View {
    @ObservedObject var vm: AppViewModel
    @Binding var showQuickCampaign: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("HarpoOutreach Dashboard")
                    .font(.largeTitle).bold()
                Text("Harpocrates Compliance Outreach Tool")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .controlSize(.regular)
            }
            Button {
                showQuickCampaign = true
            } label: {
                Label("Quick Campaign", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Status + Error Banners
struct DashboardStatusBanner: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            if !vm.currentStep.isEmpty {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("\(vm.currentStep)")
                        .font(.callout)
                    Spacer()
                }
                .padding(12)
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
            if !vm.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(vm.errorMessage)
                        .font(.callout)
                    Spacer()
                    Button("X") { vm.errorMessage = "" }
                        .buttonStyle(.plain)
                }
                .padding(12)
                .background(.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - KPI Grid (Email Pipeline)
struct DashboardKPIGrid: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Email Pipeline")
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(title: "Identifiziert", value: "\(vm.statsIdentified)", icon: "person.badge.plus", color: .gray)
                StatCard(title: "Verifiziert", value: "\(vm.statsVerified)", icon: "checkmark.shield", color: .orange)
                StatCard(title: "Gesendet", value: "\(vm.statsSent)", icon: "paperplane", color: .blue)
                StatCard(title: "Antworten", value: "\(vm.statsReplied)", icon: "envelope.open", color: .green)
                StatCard(title: "Follow-Ups", value: "\(vm.statsFollowUp)", icon: "arrow.uturn.forward", color: .purple)
            }
        }
    }
}

// MARK: - Campaign Stats
struct DashboardCampaignView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .foregroundStyle(.indigo)
                    Text("Campaigns")
                        .font(.headline)
                    Spacer()
                    let rate = vm.statsConversionRate
                    Text(String(format: "%.1f%% Conversion", rate))
                        .font(.caption.bold())
                        .foregroundStyle(rate > 10 ? .green : rate > 5 ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((rate > 10 ? Color.green : rate > 5 ? Color.orange : Color.gray).opacity(0.12))
                        .cornerRadius(6)
                }
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(title: "Unternehmen", value: "\(vm.statsCompanies)", icon: "building.2", color: .indigo)
                    StatCard(title: "Drafts bereit", value: "\(vm.statsDraftsReady)", icon: "doc.text", color: .cyan)
                    StatCard(title: "Freigegeben", value: "\(vm.statsApproved)", icon: "checkmark.circle", color: .green)
                    StatCard(title: "Follow-Up offen", value: "\(vm.statsFollowUpsPending)", icon: "clock.arrow.2.circlepath", color: .orange)
                }
                if !vm.statsIndustryCounts.isEmpty {
                    Divider()
                    Text("Unternehmen nach Branche")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let maxCount = vm.statsIndustryCounts.first?.count ?? 1
                    ForEach(vm.statsIndustryCounts.prefix(4), id: \.industry) { entry in
                        HStack(spacing: 8) {
                            Text(entry.industry)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ProgressView(value: Double(entry.count), total: Double(maxCount))
                                .frame(width: 120)
                            Text("\(entry.count)")
                                .font(.caption.bold())
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Social Posts Stats
struct DashboardSocialPostsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(.blue)
                    Text("LinkedIn Posts")
                        .font(.headline)
                    Spacer()
                    if vm.statsSocialPostsThisWeek > 0 {
                        Text("\(vm.statsSocialPostsThisWeek) diese Woche")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(title: "Posts gesamt", value: "\(vm.statsSocialPostsTotal)", icon: "doc.richtext", color: .blue)
                    StatCard(title: "LinkedIn", value: "\(vm.statsSocialPostsLinkedIn)", icon: "link", color: .indigo)
                    StatCard(title: "Twitter/X", value: "\(vm.statsSocialPostsTwitter)", icon: "bird", color: .cyan)
                    StatCard(title: "Veroeffentlicht", value: "\(vm.statsSocialPostsPublished)", icon: "checkmark.seal", color: .green)
                }
                if !vm.socialPosts.isEmpty {
                    Divider()
                    Text("Letzte Posts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(vm.socialPosts.prefix(3)) { post in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: post.platform == .linkedin ? "link" : "bird")
                                .foregroundStyle(.blue)
                                .frame(width: 16)
                            Text(post.content.components(separatedBy: "\n").first ?? "")
                                .font(.caption)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(post.createdDate, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("Noch keine Posts. Generiere deinen ersten LinkedIn Post.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Pipeline by Industry
struct DashboardPipelineView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        GroupBox("Pipeline nach Industrie") {
            VStack(spacing: 8) {
                ForEach(Industry.allCases) { industry in
                    DashboardIndustryRow(industry: industry, leads: vm.leads)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Industry Row
struct DashboardIndustryRow: View {
    let industry: Industry
    let leads: [Lead]

    var body: some View {
        let matched = leads.filter { lead in
            lead.company.lowercased().contains(industry.shortName.lowercased())
            || industry.searchTerms.lowercased()
                .components(separatedBy: ", ")
                .contains { term in lead.company.lowercased().contains(term) }
        }
        let total = max(leads.count, 1)
        HStack {
            Label(industry.shortName, systemImage: industry.icon)
                .font(.caption)
                .frame(width: 160, alignment: .leading)
            ProgressView(value: Double(matched.count), total: Double(total))
            Text("\(matched.count)")
                .font(.caption.bold())
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Recent Contacts
struct DashboardRecentView: View {
    let leads: [Lead]

    var body: some View {
        GroupBox("Letzte Kontakte") {
            if leads.isEmpty {
                Text("Noch keine Kontakte. Starte mit Prospecting.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(leads.suffix(5).reversed()) { lead in
                        DashboardLeadRow(lead: lead)
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Lead Row
struct DashboardLeadRow: View {
    let lead: Lead

    var body: some View {
        HStack {
            Circle()
                .fill(DashboardLeadRow.colorForStatus(lead.status))
                .frame(width: 8, height: 8)
            Text(lead.name).font(.callout).bold()
            Text("- \(lead.company)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(lead.status.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(DashboardLeadRow.colorForStatus(lead.status).opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }

    static func colorForStatus(_ status: LeadStatus) -> Color {
        switch status {
        case .identified: return .gray
        case .emailDrafted, .emailApproved: return .blue
        case .emailSent, .followUpDrafted, .followUpSent: return .purple
        case .replied: return .green
        case .contacted, .followedUp, .qualified, .converted, .notInterested: return .gray
        case .doNotContact: return .red
        case .closed: return .red
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title).bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}
