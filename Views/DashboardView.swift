import SwiftUI

// MARK: - Main Dashboard
struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DashboardHeaderView(vm: vm)
                DashboardStatusBanner(vm: vm)
                DashboardKPIGrid(vm: vm)
                DashboardPipelineView(leads: vm.leads)
                DashboardRecentView(leads: vm.leads)
            }
            .padding(24)
        }
    }
}

// MARK: - Header
struct DashboardHeaderView: View {
    @ObservedObject var vm: AppViewModel

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

// MARK: - KPI Grid
struct DashboardKPIGrid: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
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

// MARK: - Pipeline by Industry
struct DashboardPipelineView: View {
    let leads: [Lead]

    var body: some View {
        GroupBox("Pipeline nach Industrie") {
            VStack(spacing: 8) {
                ForEach(Industry.allCases) { industry in
                    DashboardIndustryRow(industry: industry, leads: leads)
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
        let count = leads.count
        let total = max(Double(count), 1)
        let matched = leads.filter { _ in false }.count

        HStack {
            Label(industry.rawValue, systemImage: industry.icon)
                .frame(width: 180, alignment: .leading)
            ProgressView(value: Double(matched), total: total)
            Text("\(matched)")
                .font(.caption).bold()
                .frame(width: 30)
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
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}
