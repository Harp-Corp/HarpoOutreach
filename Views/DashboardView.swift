import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                                Group {
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

                // Status
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

                // KPIs
                                                    }
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(title: "Identifiziert", value: "\(vm.statsIdentified)",
                             icon: "person.badge.plus", color: .gray)
                    StatCard(title: "Verifiziert", value: "\(vm.statsVerified)",
                             icon: "checkmark.shield", color: .orange)
                    StatCard(title: "Gesendet", value: "\(vm.statsSent)",
                             icon: "paperplane", color: .blue)
                    StatCard(title: "Antworten", value: "\(vm.statsReplied)",
                             icon: "envelope.open", color: .green)
                    StatCard(title: "Follow-Ups", value: "\(vm.statsFollowUp)",
                             icon: "arrow.uturn.forward", color: .purple)
                }

                // Pipeline pro Industrie
                GroupBox("Pipeline nach Industrie") {
                    VStack(spacing: 8) {
                        ForEach(Industry.allCases) { industry in
                            let count = vm.leads.filter {
                                $0.company.industry == industry.rawValue
                            }.count
                            HStack {
                                Label(industry.rawValue, systemImage: industry.icon)
                                    .frame(width: 180, alignment: .leading)
                                ProgressView(value: Double(count),
                                             total: max(Double(vm.leads.count), 1))
                                Text("\(count)")
                                    .font(.caption).bold()
                                    .frame(width: 30)
                            }
                        }
                    }
                    .padding(8)
                }

                // Letzte Aktivitaeten
                GroupBox("Letzte Kontakte") {
                    if vm.leads.isEmpty {
                        Text("Noch keine Kontakte. Starte mit Prospecting.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 4) {
                            ForEach(vm.leads.suffix(5).reversed()) { lead in
                                HStack {
                                    Circle()
                                        .fill(colorForStatus(lead.status))
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
                                        .background(colorForStatus(lead.status).opacity(0.2))
                                        .cornerRadius(4)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
    }

    func colorForStatus(_ status: LeadStatus) -> Color {
        switch status {
        case .identified: return .gray
        case .emailDrafted, .emailApproved: return .blue
        case .emailSent, .followUpDrafted, .followUpSent: return .purple
        case .replied: return .green
                    case .contacted, .followedUp, .qualified, .converted, .notInterested: return .gray
        case .closed: return .red
        }
    }
}

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
