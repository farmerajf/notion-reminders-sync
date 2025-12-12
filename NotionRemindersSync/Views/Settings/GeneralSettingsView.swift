import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("syncIntervalMinutes") private var syncIntervalMinutes: Int = 5
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    private let syncIntervalOptions = [1, 5, 15, 30, 60]

    var body: some View {
        Form {
            Section {
                Picker("Sync Interval", selection: $syncIntervalMinutes) {
                    ForEach(syncIntervalOptions, id: \.self) { minutes in
                        if minutes == 60 {
                            Text("1 hour").tag(minutes)
                        } else {
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                }
                .pickerStyle(.menu)

                Text("Reminders will sync with Notion every \(formattedInterval)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Sync Settings")
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }

                Text("Start NotionRemindersSync automatically when you log in")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .padding()
    }

    private var formattedInterval: String {
        if syncIntervalMinutes == 60 {
            return "hour"
        } else if syncIntervalMinutes == 1 {
            return "minute"
        } else {
            return "\(syncIntervalMinutes) minutes"
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

#Preview {
    GeneralSettingsView()
}
