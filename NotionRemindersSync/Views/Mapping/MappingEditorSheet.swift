import SwiftUI
import EventKit

struct MappingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mapping: SyncMapping?
    let onSave: (SyncMapping) -> Void

    @State private var selectedAppleList: EKCalendar? = nil
    @State private var selectedNotionDatabase: NotionDatabase? = nil
    @State private var isEnabled: Bool = true
    @State private var isLoadingLists: Bool = false
    @State private var isLoadingDatabases: Bool = false
    @State private var appleLists: [EKCalendar] = []
    @State private var notionDatabases: [NotionDatabase] = []
    @State private var errorMessage: String? = nil

    // Property mappings
    @State private var titlePropertyId: String = ""
    @State private var dueDatePropertyId: String = ""
    @State private var priorityPropertyId: String = ""

    private let remindersService = RemindersService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(mapping == nil ? "New Mapping" : "Edit Mapping")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()

            Divider()

            Form {
                // Apple Reminders List Section
                Section {
                    if isLoadingLists {
                        ProgressView("Loading lists...")
                    } else if appleLists.isEmpty {
                        Text("No Reminders lists available")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Reminders List", selection: $selectedAppleList) {
                            Text("Select a list").tag(nil as EKCalendar?)
                            ForEach(appleLists, id: \.calendarIdentifier) { list in
                                HStack {
                                    Circle()
                                        .fill(Color(cgColor: list.cgColor))
                                        .frame(width: 10, height: 10)
                                    Text(list.title)
                                }
                                .tag(list as EKCalendar?)
                            }
                        }
                    }
                } header: {
                    Label("Apple Reminders", systemImage: "checklist")
                }

                // Notion Database Section
                Section {
                    if isLoadingDatabases {
                        ProgressView("Loading databases...")
                    } else if notionDatabases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No Notion databases available")
                                .foregroundColor(.secondary)
                            Text("Make sure your Notion integration has access to at least one database.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Notion Database", selection: $selectedNotionDatabase) {
                            Text("Select a database").tag(nil as NotionDatabase?)
                            ForEach(notionDatabases) { database in
                                Text(database.title)
                                    .tag(database as NotionDatabase?)
                            }
                        }
                    }
                } header: {
                    Label("Notion", systemImage: "doc.text")
                }

                // Property Mapping Section (shown when database is selected)
                if let database = selectedNotionDatabase {
                    Section {
                        propertyMappingView(for: database)
                    } header: {
                        Label("Property Mapping", systemImage: "arrow.left.arrow.right")
                    }
                }

                // Options Section
                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Options")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 500)
        .onAppear {
            loadData()
        }
    }

    @ViewBuilder
    private func propertyMappingView(for database: NotionDatabase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title property (required)
            HStack {
                Text("Title")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $titlePropertyId) {
                    Text("Auto-detect").tag("")
                    ForEach(database.properties.filter { $0.type == "title" }) { prop in
                        Text(prop.name).tag(prop.id)
                    }
                }
                .labelsHidden()
            }

            // Due Date property
            HStack {
                Text("Due Date")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $dueDatePropertyId) {
                    Text("None").tag("")
                    ForEach(database.properties.filter { $0.type == "date" }) { prop in
                        Text(prop.name).tag(prop.id)
                    }
                }
                .labelsHidden()
            }

            // Priority property
            HStack {
                Text("Priority")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $priorityPropertyId) {
                    Text("None").tag("")
                    ForEach(database.properties.filter { $0.type == "select" }) { prop in
                        Text(prop.name).tag(prop.id)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var canSave: Bool {
        selectedAppleList != nil && selectedNotionDatabase != nil
    }

    private func loadData() {
        loadAppleLists()
        loadNotionDatabases()

        // Populate fields if editing
        if let mapping = mapping {
            isEnabled = mapping.isEnabled
            titlePropertyId = mapping.titlePropertyId
            dueDatePropertyId = mapping.dueDatePropertyId ?? ""
            priorityPropertyId = mapping.priorityPropertyId ?? ""
        }
    }

    private func loadAppleLists() {
        isLoadingLists = true

        Task {
            do {
                let hasAccess = try await remindersService.requestAccess()
                if hasAccess {
                    let lists = remindersService.getLists()
                    await MainActor.run {
                        self.appleLists = lists
                        self.isLoadingLists = false

                        // Select existing list if editing
                        if let mapping = mapping {
                            self.selectedAppleList = lists.first { $0.calendarIdentifier == mapping.appleListId }
                        }
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingLists = false
                        self.errorMessage = "No access to Reminders. Please grant access in System Settings."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingLists = false
                    self.errorMessage = "Failed to load Reminders lists: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadNotionDatabases() {
        isLoadingDatabases = true
        errorMessage = nil

        Task {
            do {
                let databases = try await NotionClient.shared.listDatabases()

                await MainActor.run {
                    self.notionDatabases = databases
                    self.isLoadingDatabases = false

                    // Select existing database if editing
                    if let mapping = mapping {
                        self.selectedNotionDatabase = databases.first { $0.id == mapping.notionDatabaseId }
                    }

                    if databases.isEmpty {
                        self.errorMessage = "No databases found. Make sure your Notion integration has access to at least one database."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingDatabases = false
                    self.errorMessage = "Failed to load Notion databases: \(error.localizedDescription)"
                    print("[MappingEditorSheet] Error loading databases: \(error)")
                }
            }
        }
    }

    private func save() {
        guard let appleList = selectedAppleList,
              let notionDatabase = selectedNotionDatabase else { return }

        // Find selected properties to get both ID and name
        let titleProp = titlePropertyId.isEmpty
            ? notionDatabase.properties.first { $0.type == "title" }
            : notionDatabase.properties.first { $0.id == titlePropertyId }

        let dueDateProp = dueDatePropertyId.isEmpty
            ? nil
            : notionDatabase.properties.first { $0.id == dueDatePropertyId }

        let priorityProp = priorityPropertyId.isEmpty
            ? nil
            : notionDatabase.properties.first { $0.id == priorityPropertyId }

        // Find checkbox property for completed status
        let completedProp = notionDatabase.properties.first { $0.type == "checkbox" }

        let newMapping = SyncMapping(
            id: mapping?.id ?? UUID(),
            appleListId: appleList.calendarIdentifier,
            appleListName: appleList.title,
            notionDatabaseId: notionDatabase.id,
            notionDatabaseName: notionDatabase.title,
            isEnabled: isEnabled,
            lastSyncDate: mapping?.lastSyncDate,
            createdAt: mapping?.createdAt ?? Date(),
            titlePropertyId: titleProp?.id ?? "",
            titlePropertyName: titleProp?.name ?? "",
            dueDatePropertyId: dueDateProp?.id,
            dueDatePropertyName: dueDateProp?.name,
            priorityPropertyId: priorityProp?.id,
            priorityPropertyName: priorityProp?.name,
            completedPropertyId: completedProp?.id,
            completedPropertyName: completedProp?.name
        )

        onSave(newMapping)
        dismiss()
    }
}

#Preview {
    MappingEditorSheet(mapping: nil) { _ in }
}
