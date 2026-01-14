import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            NotionAuthView()
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
