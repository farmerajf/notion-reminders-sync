import Foundation

/// Configuration for mapping an Apple Reminders list to a Notion database
struct SyncMapping: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var appleListId: String
    var appleListName: String
    var notionDatabaseId: String
    var notionDatabaseName: String
    var isEnabled: Bool
    var lastSyncDate: Date?
    var createdAt: Date

    // Property mappings - store both ID (for API writes) and name (for reading responses)
    var titlePropertyId: String
    var titlePropertyName: String
    var dueDatePropertyId: String?
    var dueDatePropertyName: String?
    var priorityPropertyId: String?
    var priorityPropertyName: String?
    var statusPropertyId: String?
    var statusPropertyName: String?
    var statusCompletedValue: String?
    var statusCompletedValues: [String]?
    var completedPropertyId: String?
    var completedPropertyName: String?

    init(
        id: UUID = UUID(),
        appleListId: String,
        appleListName: String,
        notionDatabaseId: String,
        notionDatabaseName: String,
        isEnabled: Bool = true,
        lastSyncDate: Date? = nil,
        createdAt: Date = Date(),
        titlePropertyId: String,
        titlePropertyName: String,
        dueDatePropertyId: String? = nil,
        dueDatePropertyName: String? = nil,
        priorityPropertyId: String? = nil,
        priorityPropertyName: String? = nil,
        statusPropertyId: String? = nil,
        statusPropertyName: String? = nil,
        statusCompletedValue: String? = nil,
        statusCompletedValues: [String]? = nil,
        completedPropertyId: String? = nil,
        completedPropertyName: String? = nil
    ) {
        self.id = id
        self.appleListId = appleListId
        self.appleListName = appleListName
        self.notionDatabaseId = notionDatabaseId
        self.notionDatabaseName = notionDatabaseName
        self.isEnabled = isEnabled
        self.lastSyncDate = lastSyncDate
        self.createdAt = createdAt
        self.titlePropertyId = titlePropertyId
        self.titlePropertyName = titlePropertyName
        self.dueDatePropertyId = dueDatePropertyId
        self.dueDatePropertyName = dueDatePropertyName
        self.priorityPropertyId = priorityPropertyId
        self.priorityPropertyName = priorityPropertyName
        self.statusPropertyId = statusPropertyId
        self.statusPropertyName = statusPropertyName
        self.statusCompletedValue = statusCompletedValue
        self.statusCompletedValues = statusCompletedValues
        self.completedPropertyId = completedPropertyId
        self.completedPropertyName = completedPropertyName
    }
}
