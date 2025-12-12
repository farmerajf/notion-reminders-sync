# Add Debug Tab to View Sync Records

## Goal
Add a Debug section to the app to view all current SyncRecords and their values in a table format.

## Files to Modify

| File | Changes |
|------|---------|
| `LocalSyncStateStore.swift` | Add `getAllSyncRecords()` and `deleteAllSyncRecords()` methods |
| `DebugSyncRecordsView.swift` | **New file** - Table view showing all sync records |
| `ContentView.swift` | Add `.debug` case to `SettingsTab` enum, sidebar, and detail view |
| `project.pbxproj` | Add new file reference |

## Implementation Details

### 1. LocalSyncStateStore.swift

Add these methods after `getSyncRecords(forMappingId:)`:

```swift
func getAllSyncRecords() -> [SyncRecord] {
    return getRecordsFromDefaults()
}

func deleteAllSyncRecords() throws {
    try saveRecordsToDefaults([])
    print("[LocalSyncStateStore] Deleted all sync records")
}
```

### 2. DebugSyncRecordsView.swift (New File)

Create in `NotionRemindersSync/Views/Settings/`:

```swift
import SwiftUI

struct DebugSyncRecordsView: View {
    @State private var syncRecords: [SyncRecord] = []
    @State private var selectedRecord: SyncRecord.ID?

    private let store = LocalSyncStateStore.shared
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sync Records")
                    .font(.headline)
                Spacer()
                Text("\(syncRecords.count) records")
                    .foregroundStyle(.secondary)
                Button("Refresh") {
                    loadRecords()
                }
                Button("Clear All", role: .destructive) {
                    clearAllRecords()
                }
            }

            Table(syncRecords, selection: $selectedRecord) {
                TableColumn("Status") { record in
                    Text(record.syncStatus.rawValue)
                        .foregroundStyle(statusColor(record.syncStatus))
                }
                .width(min: 60, ideal: 80)

                TableColumn("Apple ID") { record in
                    Text(record.appleReminderId)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Notion ID") { record in
                    Text(record.notionPageId)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Last Sync") { record in
                    Text(dateFormatter.string(from: record.lastSyncDate))
                }
                .width(min: 120, ideal: 150)

                TableColumn("Hash") { record in
                    Text(String(record.lastSyncedHash.prefix(8)))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 80)
            }
            .tableStyle(.bordered)

            if let selectedId = selectedRecord,
               let record = syncRecords.first(where: { $0.id == selectedId }) {
                GroupBox("Selected Record Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Record ID", record.id.uuidString)
                        detailRow("Mapping ID", record.mappingId.uuidString)
                        detailRow("Apple Reminder ID", record.appleReminderId)
                        detailRow("Notion Page ID", record.notionPageId)
                        detailRow("Last Synced Hash", record.lastSyncedHash)
                        detailRow("Last Apple Mod", dateFormatter.string(from: record.lastAppleModification))
                        detailRow("Last Notion Mod", dateFormatter.string(from: record.lastNotionModification))
                        detailRow("Last Sync Date", dateFormatter.string(from: record.lastSyncDate))
                        detailRow("Status", record.syncStatus.rawValue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
        }
        .padding()
        .onAppear {
            loadRecords()
        }
    }

    private func loadRecords() {
        syncRecords = store.getAllSyncRecords()
    }

    private func clearAllRecords() {
        try? store.deleteAllSyncRecords()
        loadRecords()
    }

    private func statusColor(_ status: SyncRecord.SyncStatus) -> Color {
        switch status {
        case .synced: return .green
        case .pendingToNotion, .pendingToApple: return .orange
        case .conflict: return .yellow
        case .deleted: return .gray
        case .error: return .red
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

#Preview {
    DebugSyncRecordsView()
}
```

### 3. ContentView.swift

Update the `SettingsTab` enum:

```swift
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case notion = "Notion"
    case mappings = "Mappings"
    case status = "Status"
    case debug = "Debug"  // ADD THIS

    var icon: String {
        switch self {
        case .general: return "gear"
        case .notion: return "link"
        case .mappings: return "arrow.left.arrow.right"
        case .status: return "arrow.triangle.2.circlepath"
        case .debug: return "ladybug"  // ADD THIS
        }
    }
}
```

Update `detailView(for:)`:

```swift
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
    case .debug:  // ADD THIS
        DebugSyncRecordsView()
    }
}
```

### 4. project.pbxproj

Add `DebugSyncRecordsView.swift` to the project. The file should be placed in `NotionRemindersSync/Views/Settings/`.

## Status
- [ ] Add `getAllSyncRecords()` to LocalSyncStateStore
- [ ] Add `deleteAllSyncRecords()` to LocalSyncStateStore
- [ ] Create `DebugSyncRecordsView.swift`
- [ ] Add Debug tab to ContentView.swift
- [ ] Update project.pbxproj
