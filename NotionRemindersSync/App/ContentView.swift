import SwiftUI

enum AppTab: String, CaseIterable {
    case status = "Status"
    case mappings = "Mappings"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .status: return "arrow.triangle.2.circlepath"
        case .mappings: return "arrow.left.arrow.right"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .status

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SyncStatusView()
            }
            .tabItem {
                Label(AppTab.status.rawValue, systemImage: AppTab.status.icon)
            }
            .tag(AppTab.status)

            NavigationStack {
                MappingsSettingsView()
            }
            .tabItem {
                Label(AppTab.mappings.rawValue, systemImage: AppTab.mappings.icon)
            }
            .tag(AppTab.mappings)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppTab.settings.rawValue, systemImage: AppTab.settings.icon)
            }
            .tag(AppTab.settings)
        }
    }
}

#Preview {
    ContentView()
}
