import SwiftUI

@main
struct HarpoOutreachApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}
