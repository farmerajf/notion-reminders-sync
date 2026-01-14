import Foundation
import SwiftData

/// SwiftData-backed storage for sync state with indexed queries
@MainActor
final class SwiftDataStore {
    static let shared = SwiftDataStore()

    let modelContainer: ModelContainer
    private var modelContext: ModelContext

    private init() {
        do {
            let schema = Schema([
                SDSyncMapping.self,
                SDSyncRecord.self,
                SDSyncHistoryEntry.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = modelContainer.mainContext
            print("[SwiftDataStore] Initialized successfully")
        } catch {
            fatalError("[SwiftDataStore] Failed to initialize ModelContainer: \(error)")
        }
    }

    // MARK: - SyncMapping CRUD

    func saveSyncMapping(_ mapping: SyncMapping) throws {
        let descriptor = FetchDescriptor<SDSyncMapping>(
            predicate: #Predicate { $0.id == mapping.id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: mapping)
        } else {
            let sdMapping = SDSyncMapping(
                id: mapping.id,
                appleListId: mapping.appleListId,
                appleListName: mapping.appleListName,
                notionDatabaseId: mapping.notionDatabaseId,
                notionDatabaseName: mapping.notionDatabaseName,
                isEnabled: mapping.isEnabled,
                lastSyncDate: mapping.lastSyncDate,
                createdAt: mapping.createdAt,
                titlePropertyId: mapping.titlePropertyId,
                titlePropertyName: mapping.titlePropertyName,
                dueDatePropertyId: mapping.dueDatePropertyId,
                dueDatePropertyName: mapping.dueDatePropertyName,
                priorityPropertyId: mapping.priorityPropertyId,
                priorityPropertyName: mapping.priorityPropertyName,
                statusPropertyId: mapping.statusPropertyId,
                statusPropertyName: mapping.statusPropertyName,
                statusCompletedValue: mapping.statusCompletedValue,
                statusCompletedValues: mapping.statusCompletedValues,
                completedPropertyId: mapping.completedPropertyId,
                completedPropertyName: mapping.completedPropertyName
            )
            modelContext.insert(sdMapping)
        }

        try modelContext.save()
        print("[SwiftDataStore] Saved mapping: \(mapping.id) - \(mapping.appleListName) <-> \(mapping.notionDatabaseName)")

        // Verify save by immediately fetching
        let verifyDescriptor = FetchDescriptor<SDSyncMapping>()
        let allMappings = try modelContext.fetch(verifyDescriptor)
        print("[SwiftDataStore] Verification: \(allMappings.count) total mappings in store")
    }

    func getSyncMappings() -> [SyncMapping] {
        let descriptor = FetchDescriptor<SDSyncMapping>(
            sortBy: [SortDescriptor(\.createdAt)]
        )

        do {
            let results = try modelContext.fetch(descriptor)
            print("[SwiftDataStore] getSyncMappings: fetched \(results.count) from database")
            for (i, m) in results.enumerated() {
                print("[SwiftDataStore]   [\(i)] id=\(m.id) name=\(m.appleListName) enabled=\(m.isEnabled)")
            }
            return results.map { $0.toSyncMapping() }
        } catch {
            print("[SwiftDataStore] Error fetching mappings: \(error)")
            return []
        }
    }

    func getSyncMapping(id: UUID) -> SyncMapping? {
        let descriptor = FetchDescriptor<SDSyncMapping>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try modelContext.fetch(descriptor).first?.toSyncMapping()
        } catch {
            print("[SwiftDataStore] Error fetching mapping: \(error)")
            return nil
        }
    }

    func deleteSyncMapping(id: UUID) throws {
        let descriptor = FetchDescriptor<SDSyncMapping>(
            predicate: #Predicate { $0.id == id }
        )

        if let mapping = try modelContext.fetch(descriptor).first {
            modelContext.delete(mapping)
            try modelContext.save()
            print("[SwiftDataStore] Deleted mapping: \(id)")
        }
    }

    // MARK: - SyncRecord CRUD

    func saveSyncRecord(_ record: SyncRecord) throws {
        let recordId = record.id
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate { $0.id == recordId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: record)
        } else {
            // Find the parent mapping to set the relationship
            let mappingId = record.mappingId
            let mappingDescriptor = FetchDescriptor<SDSyncMapping>(
                predicate: #Predicate { $0.id == mappingId }
            )
            let sdMapping = try modelContext.fetch(mappingDescriptor).first

            let sdRecord = SDSyncRecord(
                id: record.id,
                mappingId: record.mappingId,
                appleReminderId: record.appleReminderId,
                notionPageId: record.notionPageId,
                lastSyncedHash: record.lastSyncedHash,
                lastAppleModification: record.lastAppleModification,
                lastNotionModification: record.lastNotionModification,
                lastSyncDate: record.lastSyncDate,
                syncStatus: record.syncStatus
            )

            // Set the relationship for proper SwiftData persistence
            sdRecord.mapping = sdMapping

            modelContext.insert(sdRecord)
        }

        try modelContext.save()
    }

    func saveSyncRecords(_ records: [SyncRecord]) throws {
        for record in records {
            try saveSyncRecord(record)
        }
    }

    func getSyncRecords(forMappingId mappingId: UUID) -> [SyncRecord] {
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate { $0.mappingId == mappingId }
        )

        do {
            return try modelContext.fetch(descriptor).map { $0.toSyncRecord() }
        } catch {
            print("[SwiftDataStore] Error fetching records: \(error)")
            return []
        }
    }

    func getSyncRecord(appleReminderId: String, mappingId: UUID) -> SyncRecord? {
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate {
                $0.mappingId == mappingId && $0.appleReminderId == appleReminderId
            }
        )

        do {
            return try modelContext.fetch(descriptor).first?.toSyncRecord()
        } catch {
            print("[SwiftDataStore] Error fetching record: \(error)")
            return nil
        }
    }

    func getSyncRecord(notionPageId: String, mappingId: UUID) -> SyncRecord? {
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate {
                $0.mappingId == mappingId && $0.notionPageId == notionPageId
            }
        )

        do {
            return try modelContext.fetch(descriptor).first?.toSyncRecord()
        } catch {
            print("[SwiftDataStore] Error fetching record: \(error)")
            return nil
        }
    }

    /// Finds a sync record by its short ID (used for n:// URL handling)
    /// Uses indexed lookup on the id field
    func getSyncRecord(byShortId shortId: String) -> SyncRecord? {
        // Since shortId is derived from UUID prefix, we need to scan
        // But SwiftData makes this faster than UserDefaults
        let descriptor = FetchDescriptor<SDSyncRecord>()

        do {
            let records = try modelContext.fetch(descriptor)
            let lowercasedShortId = shortId.lowercased()
            return records.first {
                $0.shortId == lowercasedShortId
            }?.toSyncRecord()
        } catch {
            print("[SwiftDataStore] Error fetching record by shortId: \(error)")
            return nil
        }
    }

    func deleteSyncRecord(id: UUID) throws {
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate { $0.id == id }
        )

        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func deleteSyncRecords(forMappingId mappingId: UUID) throws {
        let descriptor = FetchDescriptor<SDSyncRecord>(
            predicate: #Predicate { $0.mappingId == mappingId }
        )

        let records = try modelContext.fetch(descriptor)
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    // MARK: - SyncHistory

    func saveSyncHistoryEntry(_ entry: SyncHistoryEntry) throws {
        print("[SwiftDataStore] saveSyncHistoryEntry: saving entry for mapping \(entry.mappingId)")

        // Find the parent mapping
        let mappingId = entry.mappingId
        let mappingDescriptor = FetchDescriptor<SDSyncMapping>(
            predicate: #Predicate { $0.id == mappingId }
        )
        guard let sdMapping = try modelContext.fetch(mappingDescriptor).first else {
            print("[SwiftDataStore] saveSyncHistoryEntry: ERROR - mapping not found for id \(entry.mappingId)")
            return
        }

        let sdEntry = SDSyncHistoryEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            mappingId: entry.mappingId,
            operation: entry.operation,
            itemsCreated: entry.itemsCreated,
            itemsUpdated: entry.itemsUpdated,
            itemsDeleted: entry.itemsDeleted,
            conflicts: entry.conflicts,
            errors: entry.errors
        )

        // Add through the relationship array - this is the SwiftData-native approach
        sdMapping.historyEntries.append(sdEntry)
        print("[SwiftDataStore] saveSyncHistoryEntry: appended entry \(entry.id) to mapping.historyEntries (now \(sdMapping.historyEntries.count) entries)")

        // Temporarily disabled to debug persistence issue
        // try trimHistoryIfNeeded(mappingId: entry.mappingId)

        try modelContext.save()
        print("[SwiftDataStore] saveSyncHistoryEntry: saved successfully")

        // Verify save - check both ways
        let verifyDescriptor = FetchDescriptor<SDSyncHistoryEntry>()
        let allEntries = try modelContext.fetch(verifyDescriptor)
        print("[SwiftDataStore] saveSyncHistoryEntry: verification via fetch shows \(allEntries.count) entries")
        print("[SwiftDataStore] saveSyncHistoryEntry: verification via relationship shows \(sdMapping.historyEntries.count) entries")
    }

    private func trimHistoryIfNeeded(mappingId: UUID) throws {
        var descriptor = FetchDescriptor<SDSyncHistoryEntry>(
            predicate: #Predicate { $0.mappingId == mappingId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchOffset = 100

        let oldEntries = try modelContext.fetch(descriptor)
        for entry in oldEntries {
            modelContext.delete(entry)
        }
    }

    func getSyncHistory(forMappingId mappingId: UUID, limit: Int = 50) -> [SyncHistoryEntry] {
        var descriptor = FetchDescriptor<SDSyncHistoryEntry>(
            predicate: #Predicate { $0.mappingId == mappingId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            let results = try modelContext.fetch(descriptor)
            print("[SwiftDataStore] getSyncHistory: fetched \(results.count) entries for mapping \(mappingId)")
            return results.map { $0.toSyncHistoryEntry() }
        } catch {
            print("[SwiftDataStore] Error fetching history: \(error)")
            return []
        }
    }
}
