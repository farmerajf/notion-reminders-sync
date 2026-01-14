import SwiftUI

struct MappingsSettingsView: View {
    @State private var mappings: [SyncMapping] = []
    @State private var showingAddSheet = false
    @State private var selectedMapping: SyncMapping? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private let syncStateStore = LocalSyncStateStore.shared

    var body: some View {
        List {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            if mappings.isEmpty && !isLoading {
                emptyStateRow
            } else {
                ForEach(mappings) { mapping in
                    MappingRowView(mapping: mapping)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMapping = mapping
                        }
                        .contextMenu {
                            Button("Edit") {
                                selectedMapping = mapping
                            }

                            Button("Delete", role: .destructive) {
                                deleteMapping(mapping)
                            }
                        }
                }
                .onDelete(perform: deleteMappings)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 8)
        }
        .navigationTitle("Mappings")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            loadMappings()
        }
        .sheet(isPresented: $showingAddSheet) {
            MappingEditorSheet(mapping: nil) { newMapping in
                saveMapping(newMapping)
            }
        }
        .sheet(item: $selectedMapping) { mapping in
            MappingEditorSheet(mapping: mapping) { updatedMapping in
                saveMapping(updatedMapping)
            }
        }
    }

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Mappings")
                .font(.headline)
            Text("Create a mapping to sync an Apple Reminders list with a Notion database.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    private func loadMappings() {
        isLoading = true
        errorMessage = nil

        let loadedMappings = syncStateStore.getSyncMappings()
        self.mappings = loadedMappings
        self.isLoading = false
        print("[MappingsSettingsView] Loaded \(loadedMappings.count) mappings")
    }

    private func saveMapping(_ mapping: SyncMapping) {
        do {
            try syncStateStore.saveSyncMapping(mapping)
            if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
                mappings[index] = mapping
            } else {
                mappings.append(mapping)
            }
            print("[MappingsSettingsView] Saved mapping: \(mapping.appleListName) <-> \(mapping.notionDatabaseName)")
        } catch {
            self.errorMessage = "Failed to save mapping: \(error.localizedDescription)"
            print("[MappingsSettingsView] Error saving mapping: \(error)")
        }
    }

    private func deleteMapping(_ mapping: SyncMapping) {
        do {
            try syncStateStore.deleteSyncMapping(id: mapping.id)
            mappings.removeAll { $0.id == mapping.id }
            print("[MappingsSettingsView] Deleted mapping: \(mapping.id)")
        } catch {
            self.errorMessage = "Failed to delete mapping: \(error.localizedDescription)"
            print("[MappingsSettingsView] Error deleting mapping: \(error)")
        }
    }

    private func deleteMappings(at offsets: IndexSet) {
        for index in offsets {
            deleteMapping(mappings[index])
        }
    }
}

// MARK: - Mapping Row View
struct MappingRowView: View {
    let mapping: SyncMapping

    var body: some View {
        HStack(spacing: 12) {
            // Apple Reminders icon
            Image(systemName: "checklist")
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.appleListName)
                    .font(.body)

                Text("Apple Reminders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.caption)

            // Notion icon
            Image(systemName: "doc.text")
                .foregroundColor(.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.notionDatabaseName)
                    .font(.body)

                Text("Notion Database")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(mapping.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MappingsSettingsView()
}
