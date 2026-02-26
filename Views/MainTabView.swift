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
                Label("Content", systemImage: "text.bubble")
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
                case 3: SocialPostView().environmentObject(vm)
                case 4: AnalyticsView(vm: vm)
                case 5: SettingsView(vm: vm)
                default: DashboardView(vm: vm)
                }
            }
        }
        .navigationTitle("HarpoOutreach")
    }
}
