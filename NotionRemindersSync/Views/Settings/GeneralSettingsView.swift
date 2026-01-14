import SwiftUI

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Foreground sync runs every 5 minutes while the app is open.")
                    .font(.subheadline)
                Text("Background sync uses iOS Background App Refresh for best-effort updates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Sync Info")
            }
        }
        .navigationTitle("General")
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
