import SwiftUI

struct SyncStatusView: View {
    private let syncEngine = SyncEngine.shared
    private let syncStateStore = LocalSyncStateStore.shared

    @State private var isSyncing = false
    @State private var lastSyncDate: Date? = nil
    @State private var syncHistory: [SyncHistoryEntry] = []
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current status header
            currentStatusSection
                .padding()

            Divider()

            // Sync history
            if syncHistory.isEmpty {
                emptyHistoryView
            } else {
                historyList
            }
        }
        .navigationTitle("Status")
        .onAppear {
            loadState()
        }
    }

    private func loadState() {
        lastSyncDate = syncEngine.lastSyncDate
        isSyncing = syncEngine.isSyncing
        if let error = syncEngine.lastError {
            errorMessage = error.localizedDescription
        }
        // Load sync history from the first mapping (or could aggregate all)
        let mappings = syncStateStore.getSyncMappings()
        if let firstMapping = mappings.first {
            syncHistory = Array(syncStateStore.getSyncHistory(forMappingId: firstMapping.id, limit: 20))
        }
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Status")
                        .font(.headline)

                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Idle")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)
                }

                Spacer()

                Button(action: syncNow) {
                    HStack(spacing: 4) {
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
            }

            if let lastSync = lastSyncDate {
                HStack {
                    Text("Last sync:")
                        .foregroundColor(.secondary)
                    Text(lastSync, style: .relative)
                    Text("ago")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.orange)
                }
                .font(.caption)
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Sync History")
                .font(.headline)

            Text("Sync history will appear here after your first sync.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        List(syncHistory) { entry in
            SyncHistoryRowView(entry: entry)
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
                    lastSyncDate = syncEngine.lastSyncDate
                    loadState() // Reload history
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    errorMessage = error.localizedDescription
                    print("[SyncStatusView] Sync failed: \(error)")
                }
            }
        }
    }
}

// MARK: - History Row View
struct SyncHistoryRowView: View {
    let entry: SyncHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: operationIcon)
                    .foregroundColor(operationColor)

                Text(entry.timestamp, style: .date)
                    .font(.subheadline)

                Text(entry.timestamp, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if !entry.errors.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 12) {
                if entry.itemsCreated > 0 {
                    Label("\(entry.itemsCreated) created", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if entry.itemsUpdated > 0 {
                    Label("\(entry.itemsUpdated) updated", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if entry.itemsDeleted > 0 {
                    Label("\(entry.itemsDeleted) deleted", systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if entry.conflicts > 0 {
                    Label("\(entry.conflicts) conflicts", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var operationIcon: String {
        switch entry.operation {
        case .fullSync:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .incrementalSync:
            return "arrow.triangle.2.circlepath"
        case .manualSync:
            return "hand.tap"
        }
    }

    private var operationColor: Color {
        switch entry.operation {
        case .fullSync:
            return .blue
        case .incrementalSync:
            return .green
        case .manualSync:
            return .orange
        }
    }
}

#Preview {
    SyncStatusView()
}
