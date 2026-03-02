import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = AppViewModel()
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag(0)
                Label("Prospecting", systemImage: "magnifyingglass")
                    .tag(1)
                Label("Campaigns", systemImage: "paperplane.fill")
                    .tag(2)
                Label("Content & Campaigns", systemImage: "text.bubble")
                    .tag(3)
                Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(4)
                Label("Einstellungen", systemImage: "gear")
                    .tag(5)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch selectedTab {
                case 0: DashboardView(vm: vm)
                case 1: ProspectingView(vm: vm)
                case 2: CampaignsView(vm: vm)
                case 3: ContentCampaignView(vm: vm)
                case 4: AnalyticsView(vm: vm)
                case 5: SettingsView(vm: vm)
                default: DashboardView(vm: vm)
                }
            }
        }
        .navigationTitle("HarpoOutreach")
    }
}

// MARK: - Content & Campaigns Hub
// Combines Post-Generierung + Quick Campaign in one tab
// Workflow: Generate Post -> optionally convert to Newsletter Campaign -> select recipients -> create email drafts
struct ContentCampaignView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedSegment = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with segment picker
            HStack {
                Text("Content & Campaigns")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Picker("", selection: $selectedSegment) {
                    Text("Post generieren").tag(0)
                    Text("Quick Campaign").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 350)
            }
            .padding()

            Divider()

            // Content based on segment
            switch selectedSegment {
            case 0:
                SocialPostView()
                    .environmentObject(vm)
            case 1:
                QuickCampaignView(vm: vm)
            default:
                SocialPostView()
                    .environmentObject(vm)
            }
        }
    }
}
