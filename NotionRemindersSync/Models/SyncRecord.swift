import Foundation

/// Tracks sync state for individual items
struct SyncRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let mappingId: UUID
    var appleReminderId: String
    var notionPageId: String
    var lastSyncedHash: String
    var lastAppleModification: Date
    var lastNotionModification: Date
    var lastSyncDate: Date
    var syncStatus: SyncStatus

    /// Short identifier derived from UUID for use in n:// URLs
    var shortId: String {
        // Use first 8 hex characters of UUID (lowercase, no dashes)
        String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    /// Checks if this record matches a given short ID
    func matches(shortId: String) -> Bool {
        self.shortId == shortId.lowercased()
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
        syncStatus: SyncStatus = .synced
    ) {
        self.id = id
        self.mappingId = mappingId
        self.appleReminderId = appleReminderId
        self.notionPageId = notionPageId
        self.lastSyncedHash = lastSyncedHash
        self.lastAppleModification = lastAppleModification
        self.lastNotionModification = lastNotionModification
        self.lastSyncDate = lastSyncDate
        self.syncStatus = syncStatus
    }

    enum SyncStatus: String, Codable {
        case synced
        case pendingToNotion
        case pendingToApple
        case conflict
        case deleted
        case error
    }
}

/// Log of sync operations for user visibility
struct SyncHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mappingId: UUID
    let operation: SyncOperation
    let itemsCreated: Int
    let itemsUpdated: Int
    let itemsDeleted: Int
    let conflicts: Int
    let errors: [String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mappingId: UUID,
        operation: SyncOperation,
        itemsCreated: Int = 0,
        itemsUpdated: Int = 0,
        itemsDeleted: Int = 0,
        conflicts: Int = 0,
        errors: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mappingId = mappingId
        self.operation = operation
        self.itemsCreated = itemsCreated
        self.itemsUpdated = itemsUpdated
        self.itemsDeleted = itemsDeleted
        self.conflicts = conflicts
        self.errors = errors
    }

    enum SyncOperation: String, Codable {
        case fullSync
        case incrementalSync
        case manualSync
    }
}
