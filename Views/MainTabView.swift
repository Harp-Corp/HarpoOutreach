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
                            Label("Social Posts", systemImage: "text.bubble")
                    .tag(7)
                Label("Pipeline", systemImage: "list.bullet.rectangle")
                    .tag(8)
                Label("Einstellungen", systemImage: "gear")
                    .tag(9)
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
                            case 7: SocialPostView().environmentObject(vm)
                case 8: OutreachPipelineView(vm: vm)
                case 9: SettingsView(vm: vm)
                default: DashboardView(vm: vm)
                }
            }
        }
        .navigationTitle("HarpoOutreach")
    }
}
