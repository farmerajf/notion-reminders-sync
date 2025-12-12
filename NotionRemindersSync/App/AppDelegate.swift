import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let syncScheduler = SyncScheduler.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startSyncScheduler()
    }

    private func startSyncScheduler() {
        // Start the sync scheduler to enable automatic background syncing
        syncScheduler.start()
        print("[AppDelegate] Sync scheduler started")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Sync Status")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover for quick status view
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 200)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "NotionRemindersSync" || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    private let syncEngine = SyncEngine.shared

    @State private var lastSyncTime: Date? = nil
    @State private var isSyncing = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
                Text("Notion Reminders Sync")
                    .font(.headline)
            }

            Divider()

            if let lastSync = lastSyncTime {
                HStack {
                    Text("Last sync:")
                        .foregroundColor(.secondary)
                    Text(lastSync, style: .relative)
                }
                .font(.caption)
            } else {
                Text("Not synced yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            Divider()

            Button(action: syncNow) {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isSyncing ? "Syncing..." : "Sync Now")
                }
            }
            .disabled(isSyncing)

            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                }
            }

            Divider()

            Button(action: quit) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                }
            }
        }
        .padding()
        .frame(width: 250)
        .onAppear {
            loadState()
        }
    }

    private func loadState() {
        lastSyncTime = syncEngine.lastSyncDate
        isSyncing = syncEngine.isSyncing
        if let error = syncEngine.lastError {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = nil
        }
    }

    private func syncNow() {
        isSyncing = true
        errorMessage = nil

        Task {
            do {
                try await syncEngine.syncAll()

                await MainActor.run {
                    isSyncing = false
                    lastSyncTime = syncEngine.lastSyncDate
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    errorMessage = error.localizedDescription
                    print("[MenuBarView] Sync failed: \(error)")
                }
            }
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Open the Settings window via keyboard shortcut simulation
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        // Fallback: just activate the app and show main window
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
