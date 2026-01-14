import SwiftUI

struct SyncStatusView: View {
    private let syncEngine = SyncEngine.shared
    private var syncStateStore: LocalSyncStateStore { LocalSyncStateStore.shared }

    @State private var syncHistory: [SyncHistoryEntry] = []
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            Section {
                statusRow

                if let lastSync = syncEngine.lastSyncDate {
                    lastSyncRow(lastSync)
                }

                if let error = errorMessage {
                    errorRow(error)
                }
            }

            Section("History") {
                if syncHistory.isEmpty {
                    emptyHistoryRow
                } else {
                    ForEach(syncHistory) { entry in
                        SyncHistoryRowView(entry: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Status")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: syncNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(syncEngine.isSyncing)
            }
        }
        .onAppear {
            loadState()
        }
        .onChange(of: syncEngine.isSyncing) { wasSyncing, isSyncing in
            print("[SyncStatusView] onChange: isSyncing changed from \(wasSyncing) to \(isSyncing)")
            // Reload history when sync completes (transitions from syncing to idle)
            if wasSyncing && !isSyncing {
                print("[SyncStatusView] onChange: sync completed, reloading state")
                loadState()
            }
        }
    }

    private func loadState() {
        if let error = syncEngine.lastError {
            errorMessage = error.localizedDescription
        }
        // Load sync history from the first mapping (or could aggregate all)
        let mappings = syncStateStore.getSyncMappings()
        print("[SyncStatusView] loadState: found \(mappings.count) mappings")
        if let firstMapping = mappings.first {
            let history = syncStateStore.getSyncHistory(forMappingId: firstMapping.id, limit: 20)
            print("[SyncStatusView] loadState: found \(history.count) history entries for mapping \(firstMapping.id)")
            syncHistory = Array(history)
        } else {
            print("[SyncStatusView] loadState: no mappings found, cannot load history")
            syncHistory = []
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Status")

            Spacer()

            HStack(spacing: 6) {
                if syncEngine.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
                Text(syncEngine.isSyncing ? "Syncing" : "Idle")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func lastSyncRow(_ date: Date) -> some View {
        HStack {
            Text("Last Sync")
            Spacer()
            Text(date, style: .relative)
                .foregroundColor(.secondary)
            Text("ago")
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

    private func errorRow(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .foregroundColor(.orange)
            .font(.subheadline)
    }

    private var emptyHistoryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Sync History")
                .font(.subheadline)
            Text("Sync history will appear here after your first sync.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private func syncNow() {
        print("[SyncStatusView] syncNow called")
        errorMessage = nil

        Task {
            do {
                print("[SyncStatusView] Starting syncAll...")
                try await syncEngine.syncAll()
                print("[SyncStatusView] syncAll completed successfully")

                await MainActor.run {
                    loadState() // Reload history
                }
            } catch {
                await MainActor.run {
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
        HStack(alignment: .top, spacing: 12) {
            HStack {
                Image(systemName: operationIcon)
                    .foregroundColor(operationColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.timestamp, style: .date)
                        .font(.subheadline)

                    Text(entry.timestamp, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !entry.errors.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if entry.itemsCreated > 0 {
                    Label("\(entry.itemsCreated) created", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if entry.itemsUpdated > 0 {
                    Text(updateText)
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

    private var updateText: String {
        if entry.itemsUpdated == 1 {
            return "1 update"
        }
        return "\(entry.itemsUpdated) updates"
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
