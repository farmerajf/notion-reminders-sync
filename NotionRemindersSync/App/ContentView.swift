import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case notion = "Notion"
    case mappings = "Mappings"
    case status = "Status"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .notion: return "link"
        case .mappings: return "arrow.left.arrow.right"
        case .status: return "arrow.triangle.2.circlepath"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            detailView(for: selectedTab)
                .frame(minWidth: 450, minHeight: 350)
        }
        .frame(minWidth: 650, minHeight: 400)
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .notion:
            NotionAuthView()
        case .mappings:
            MappingsSettingsView()
        case .status:
            SyncStatusView()
        }
    }
}

#Preview {
    ContentView()
}
