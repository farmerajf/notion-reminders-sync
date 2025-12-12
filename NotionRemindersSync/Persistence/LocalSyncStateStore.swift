import Foundation

/// Local UserDefaults-backed storage for sync state (fallback when CloudKit unavailable)
@Observable
final class LocalSyncStateStore {
    static let shared = LocalSyncStateStore()

    private let defaults = UserDefaults.standard

    // Keys
    private let mappingsKey = "syncMappings"
    private let recordsKey = "syncRecords"
    private let historyKey = "syncHistory"

    private init() {}

    // MARK: - SyncMapping CRUD

    func saveSyncMapping(_ mapping: SyncMapping) throws {
        var mappings = getMappingsFromDefaults()
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
        try saveMappingsToDefaults(mappings)
        print("[LocalSyncStateStore] Saved mapping: \(mapping.id)")
    }

    func getSyncMappings() -> [SyncMapping] {
        let mappings = getMappingsFromDefaults()
        print("[LocalSyncStateStore] Loaded \(mappings.count) mappings")
        return mappings
    }

    func getSyncMapping(id: UUID) -> SyncMapping? {
        return getMappingsFromDefaults().first { $0.id == id }
    }

    func deleteSyncMapping(id: UUID) throws {
        var mappings = getMappingsFromDefaults()
        mappings.removeAll { $0.id == id }
        try saveMappingsToDefaults(mappings)

        // Also delete associated sync records
        var records = getRecordsFromDefaults()
        records.removeAll { $0.mappingId == id }
        try saveRecordsToDefaults(records)

        print("[LocalSyncStateStore] Deleted mapping: \(id)")
    }

    // MARK: - SyncRecord CRUD

    func saveSyncRecord(_ record: SyncRecord) throws {
        var records = getRecordsFromDefaults()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try saveRecordsToDefaults(records)
    }

    func saveSyncRecords(_ newRecords: [SyncRecord]) throws {
        var records = getRecordsFromDefaults()
        for record in newRecords {
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index] = record
            } else {
                records.append(record)
            }
        }
        try saveRecordsToDefaults(records)
    }

    func getSyncRecords(forMappingId mappingId: UUID) -> [SyncRecord] {
        return getRecordsFromDefaults().filter { $0.mappingId == mappingId }
    }

    func getSyncRecord(appleReminderId: String, mappingId: UUID) -> SyncRecord? {
        return getRecordsFromDefaults().first {
            $0.mappingId == mappingId && $0.appleReminderId == appleReminderId
        }
    }

    func getSyncRecord(notionPageId: String, mappingId: UUID) -> SyncRecord? {
        return getRecordsFromDefaults().first {
            $0.mappingId == mappingId && $0.notionPageId == notionPageId
        }
    }

    func deleteSyncRecord(id: UUID) throws {
        var records = getRecordsFromDefaults()
        records.removeAll { $0.id == id }
        try saveRecordsToDefaults(records)
    }

    func deleteSyncRecords(forMappingId mappingId: UUID) throws {
        var records = getRecordsFromDefaults()
        records.removeAll { $0.mappingId == mappingId }
        try saveRecordsToDefaults(records)
    }

    // MARK: - SyncHistory

    func saveSyncHistoryEntry(_ entry: SyncHistoryEntry) throws {
        var history = getHistoryFromDefaults()
        history.insert(entry, at: 0)
        // Keep only last 100 entries
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        try saveHistoryToDefaults(history)
    }

    func getSyncHistory(forMappingId mappingId: UUID, limit: Int = 50) -> [SyncHistoryEntry] {
        return Array(getHistoryFromDefaults()
            .filter { $0.mappingId == mappingId }
            .prefix(limit))
    }

    // MARK: - Private Helpers

    private func getMappingsFromDefaults() -> [SyncMapping] {
        guard let data = defaults.data(forKey: mappingsKey) else { return [] }
        do {
            return try JSONDecoder().decode([SyncMapping].self, from: data)
        } catch {
            print("[LocalSyncStateStore] Error decoding mappings: \(error)")
            return []
        }
    }

    private func saveMappingsToDefaults(_ mappings: [SyncMapping]) throws {
        let data = try JSONEncoder().encode(mappings)
        defaults.set(data, forKey: mappingsKey)
    }

    private func getRecordsFromDefaults() -> [SyncRecord] {
        guard let data = defaults.data(forKey: recordsKey) else { return [] }
        do {
            return try JSONDecoder().decode([SyncRecord].self, from: data)
        } catch {
            print("[LocalSyncStateStore] Error decoding records: \(error)")
            return []
        }
    }

    private func saveRecordsToDefaults(_ records: [SyncRecord]) throws {
        let data = try JSONEncoder().encode(records)
        defaults.set(data, forKey: recordsKey)
    }

    private func getHistoryFromDefaults() -> [SyncHistoryEntry] {
        guard let data = defaults.data(forKey: historyKey) else { return [] }
        do {
            return try JSONDecoder().decode([SyncHistoryEntry].self, from: data)
        } catch {
            print("[LocalSyncStateStore] Error decoding history: \(error)")
            return []
        }
    }

    private func saveHistoryToDefaults(_ history: [SyncHistoryEntry]) throws {
        let data = try JSONEncoder().encode(history)
        defaults.set(data, forKey: historyKey)
    }
}
