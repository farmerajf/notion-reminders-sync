import SwiftUI
import UIKit

/// Tracks app-wide state for URL redirects
@Observable
final class AppState {
    static let shared = AppState()
    var isRedirecting = false
    private init() {}
}

@main
struct NotionRemindersSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                // Show "Opening" overlay when redirecting via n:// link
                if appState.isRedirecting {
                    OpeningOverlayView()
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    triggerSyncInBackground()
                }
            }
        }
    }

    private func triggerSyncInBackground() {
        print("[App] App became active, triggering background sync")
        Task.detached(priority: .utility) {
            do {
                try await SyncEngine.shared.syncAll()
                print("[App] Background sync completed")
            } catch {
                print("[App] Background sync failed: \(error)")
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "n" else {
            print("[App] Ignoring URL with scheme: \(url.scheme ?? "nil")")
            return
        }

        // Extract shortId from n://shortId
        let shortId = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !shortId.isEmpty else {
            print("[App] No shortId in URL: \(url)")
            return
        }

        print("[App] Handling n:// URL with shortId: \(shortId)")

        // Show the "Opening" overlay
        appState.isRedirecting = true

        // Look up the sync record
        guard let record = LocalSyncStateStore.shared.getSyncRecord(byShortId: shortId) else {
            print("[App] No sync record found for shortId: \(shortId)")
            appState.isRedirecting = false
            return
        }

        // Construct Notion deep link URL
        let notionPageId = record.notionPageId.replacingOccurrences(of: "-", with: "")
        guard let notionURL = URL(string: "notion://notion.so/\(notionPageId)") else {
            print("[App] Failed to construct Notion URL")
            appState.isRedirecting = false
            return
        }

        print("[App] Opening Notion page: \(notionURL)")

        // Open Notion app (non-blocking)
        UIApplication.shared.open(notionURL, options: [:]) { success in
            if success {
                print("[App] Successfully opened Notion")
            } else {
                // Fallback to web URL if Notion app isn't installed
                if let webURL = URL(string: "https://notion.so/\(notionPageId)") {
                    UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
                    print("[App] Opened Notion in browser as fallback")
                }
            }
            // Reset state after redirect completes
            DispatchQueue.main.async {
                appState.isRedirecting = false
            }
        }
    }
}

/// Simple overlay shown while redirecting to Notion
struct OpeningOverlayView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Opening Notion...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
