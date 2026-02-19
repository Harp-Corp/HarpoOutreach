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
                Label("Kontakte", systemImage: "person.2.fill")
                    .tag(2)
                Label("Email Drafts", systemImage: "envelope.badge")
                    .tag(3)
                Label("Outbox", systemImage: "paperplane.fill")
                    .tag(4)
                Label("Inbox / Follow-Up", systemImage: "tray.full.fill")
                    .tag(5)
                Label("Google Sheet", systemImage: "tablecells")
                    .tag(6)
                
                Divider()
                
                Label("Content Studio", systemImage: "sparkles")
                    .tag(8)
                Label("Campaigns", systemImage: "megaphone.fill")
                    .tag(9)
                
                Divider()
                
                Label("Einstellungen", systemImage: "gear")
                    .tag(7)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch selectedTab {
                case 0: DashboardView(vm: vm)
                case 1: ProspectingView(vm: vm)
                case 2: ContactListView(vm: vm)
                case 3: EmailDraftView(vm: vm)
                case 4: OutboxView(vm: vm)
                case 5: InboxFollowUpView(vm: vm)
                case 6: SheetLogView(vm: vm)
                case 7: SettingsView(vm: vm)
                case 8: ContentGenerationView(viewModel: vm)
                case 9: NewsletterCampaignView(viewModel: vm)
                default: DashboardView(vm: vm)
                }
            }
        }
        .navigationTitle("HarpoOutreach")
    }
}
