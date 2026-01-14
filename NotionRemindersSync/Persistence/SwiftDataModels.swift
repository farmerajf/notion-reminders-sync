import Foundation
import SwiftData

// MARK: - SwiftData Models

@Model
final class SDSyncMapping {
    @Attribute(.unique) var id: UUID
    var appleListId: String
    var appleListName: String
    var notionDatabaseId: String
    var notionDatabaseName: String
    var isEnabled: Bool
    var lastSyncDate: Date?
    var createdAt: Date

    // Property mappings
    var titlePropertyId: String
    var titlePropertyName: String
    var dueDatePropertyId: String?
    var dueDatePropertyName: String?
    var priorityPropertyId: String?
    var priorityPropertyName: String?
    var statusPropertyId: String?
    var statusPropertyName: String?
    var statusCompletedValue: String?
    var statusCompletedValuesData: Data? // Store [String] as JSON
    var completedPropertyId: String?
    var completedPropertyName: String?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \SDSyncRecord.mapping)
    var records: [SDSyncRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \SDSyncHistoryEntry.mapping)
    var historyEntries: [SDSyncHistoryEntry] = []

    var statusCompletedValues: [String]? {
        get {
            guard let data = statusCompletedValuesData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            statusCompletedValuesData = try? JSONEncoder().encode(newValue)
        }
    }

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

    /// Convert to value type for use in app
    func toSyncMapping() -> SyncMapping {
        SyncMapping(
            id: id,
            appleListId: appleListId,
            appleListName: appleListName,
            notionDatabaseId: notionDatabaseId,
            notionDatabaseName: notionDatabaseName,
            isEnabled: isEnabled,
            lastSyncDate: lastSyncDate,
            createdAt: createdAt,
            titlePropertyId: titlePropertyId,
            titlePropertyName: titlePropertyName,
            dueDatePropertyId: dueDatePropertyId,
            dueDatePropertyName: dueDatePropertyName,
            priorityPropertyId: priorityPropertyId,
            priorityPropertyName: priorityPropertyName,
            statusPropertyId: statusPropertyId,
            statusPropertyName: statusPropertyName,
            statusCompletedValue: statusCompletedValue,
            statusCompletedValues: statusCompletedValues,
            completedPropertyId: completedPropertyId,
            completedPropertyName: completedPropertyName
        )
    }

    /// Update from value type
    func update(from mapping: SyncMapping) {
        appleListId = mapping.appleListId
        appleListName = mapping.appleListName
        notionDatabaseId = mapping.notionDatabaseId
        notionDatabaseName = mapping.notionDatabaseName
        isEnabled = mapping.isEnabled
        lastSyncDate = mapping.lastSyncDate
        titlePropertyId = mapping.titlePropertyId
        titlePropertyName = mapping.titlePropertyName
        dueDatePropertyId = mapping.dueDatePropertyId
        dueDatePropertyName = mapping.dueDatePropertyName
        priorityPropertyId = mapping.priorityPropertyId
        priorityPropertyName = mapping.priorityPropertyName
        statusPropertyId = mapping.statusPropertyId
        statusPropertyName = mapping.statusPropertyName
        statusCompletedValue = mapping.statusCompletedValue
        statusCompletedValues = mapping.statusCompletedValues
        completedPropertyId = mapping.completedPropertyId
        completedPropertyName = mapping.completedPropertyName
    }
}

@Model
final class SDSyncRecord {
    @Attribute(.unique) var id: UUID
    var mappingId: UUID
    var appleReminderId: String
    var notionPageId: String
    var lastSyncedHash: String
    var lastAppleModification: Date
    var lastNotionModification: Date
    var lastSyncDate: Date
    var syncStatusRaw: String

    var mapping: SDSyncMapping?

    var syncStatus: SyncRecord.SyncStatus {
        get { SyncRecord.SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Short identifier derived from UUID for use in n:// URLs
    var shortId: String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    init(
        id: UUID = UUID(),
        mappingId: UUID,
        appleReminderId: String,
        notionPageId: String,
        lastSyncedHash: String,
        lastAppleModification: Date,
        lastNotionModification: Date,
        lastSyncDate: Date = Date(),
        syncStatus: SyncRecord.SyncStatus = .synced
    ) {
        self.id = id
        self.mappingId = mappingId
        self.appleReminderId = appleReminderId
        self.notionPageId = notionPageId
        self.lastSyncedHash = lastSyncedHash
        self.lastAppleModification = lastAppleModification
        self.lastNotionModification = lastNotionModification
        self.lastSyncDate = lastSyncDate
        self.syncStatusRaw = syncStatus.rawValue
    }

    /// Convert to value type
    func toSyncRecord() -> SyncRecord {
        SyncRecord(
            id: id,
            mappingId: mappingId,
            appleReminderId: appleReminderId,
            notionPageId: notionPageId,
            lastSyncedHash: lastSyncedHash,
            lastAppleModification: lastAppleModification,
            lastNotionModification: lastNotionModification,
            lastSyncDate: lastSyncDate,
            syncStatus: syncStatus
        )
    }

    /// Update from value type
    func update(from record: SyncRecord) {
        appleReminderId = record.appleReminderId
        notionPageId = record.notionPageId
        lastSyncedHash = record.lastSyncedHash
        lastAppleModification = record.lastAppleModification
        lastNotionModification = record.lastNotionModification
        lastSyncDate = record.lastSyncDate
        syncStatus = record.syncStatus
    }
}

@Model
final class SDSyncHistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var mappingId: UUID
    var operationRaw: String
    var itemsCreated: Int
    var itemsUpdated: Int
    var itemsDeleted: Int
    var conflicts: Int
    var errorsData: Data? // Store [String] as JSON

    var mapping: SDSyncMapping?

    var operation: SyncHistoryEntry.SyncOperation {
        get { SyncHistoryEntry.SyncOperation(rawValue: operationRaw) ?? .incrementalSync }
        set { operationRaw = newValue.rawValue }
    }

    var errors: [String] {
        get {
            guard let data = errorsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            errorsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mappingId: UUID,
        operation: SyncHistoryEntry.SyncOperation,
        itemsCreated: Int = 0,
        itemsUpdated: Int = 0,
        itemsDeleted: Int = 0,
        conflicts: Int = 0,
        errors: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mappingId = mappingId
        self.operationRaw = operation.rawValue
        self.itemsCreated = itemsCreated
        self.itemsUpdated = itemsUpdated
        self.itemsDeleted = itemsDeleted
        self.conflicts = conflicts
        self.errors = errors
    }

    /// Convert to value type
    func toSyncHistoryEntry() -> SyncHistoryEntry {
        SyncHistoryEntry(
            id: id,
            timestamp: timestamp,
            mappingId: mappingId,
            operation: operation,
            itemsCreated: itemsCreated,
            itemsUpdated: itemsUpdated,
            itemsDeleted: itemsDeleted,
            conflicts: conflicts,
            errors: errors
        )
    }
}
