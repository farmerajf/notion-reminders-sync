import Foundation

/// Sync state store that delegates to SwiftDataStore
/// Maintains the same interface for backward compatibility
@MainActor
final class LocalSyncStateStore {
    static let shared = LocalSyncStateStore()

    private var swiftDataStore: SwiftDataStore { SwiftDataStore.shared }

    private init() {}

    /// Call this on app launch to migrate any existing UserDefaults data
    func migrateIfNeeded() {
        swiftDataStore.migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - SyncMapping CRUD

    func saveSyncMapping(_ mapping: SyncMapping) throws {
        try swiftDataStore.saveSyncMapping(mapping)
    }

    func getSyncMappings() -> [SyncMapping] {
        return swiftDataStore.getSyncMappings()
    }

    func getSyncMapping(id: UUID) -> SyncMapping? {
        return swiftDataStore.getSyncMapping(id: id)
    }

    func deleteSyncMapping(id: UUID) throws {
        try swiftDataStore.deleteSyncMapping(id: id)
    }

    // MARK: - SyncRecord CRUD

    func saveSyncRecord(_ record: SyncRecord) throws {
        try swiftDataStore.saveSyncRecord(record)
    }

    func saveSyncRecords(_ records: [SyncRecord]) throws {
        try swiftDataStore.saveSyncRecords(records)
    }

    func getSyncRecords(forMappingId mappingId: UUID) -> [SyncRecord] {
        return swiftDataStore.getSyncRecords(forMappingId: mappingId)
    }

    func getSyncRecord(appleReminderId: String, mappingId: UUID) -> SyncRecord? {
        return swiftDataStore.getSyncRecord(appleReminderId: appleReminderId, mappingId: mappingId)
    }

    func getSyncRecord(notionPageId: String, mappingId: UUID) -> SyncRecord? {
        return swiftDataStore.getSyncRecord(notionPageId: notionPageId, mappingId: mappingId)
    }

    /// Finds a sync record by its short ID (used for n:// URL handling)
    func getSyncRecord(byShortId shortId: String) -> SyncRecord? {
        return swiftDataStore.getSyncRecord(byShortId: shortId)
    }

    func deleteSyncRecord(id: UUID) throws {
        try swiftDataStore.deleteSyncRecord(id: id)
    }

    func deleteSyncRecords(forMappingId mappingId: UUID) throws {
        try swiftDataStore.deleteSyncRecords(forMappingId: mappingId)
    }

    // MARK: - SyncHistory

    func saveSyncHistoryEntry(_ entry: SyncHistoryEntry) throws {
        try swiftDataStore.saveSyncHistoryEntry(entry)
    }

    func getSyncHistory(forMappingId mappingId: UUID, limit: Int = 50) -> [SyncHistoryEntry] {
        return swiftDataStore.getSyncHistory(forMappingId: mappingId, limit: limit)
    }
}
