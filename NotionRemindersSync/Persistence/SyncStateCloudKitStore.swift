import CloudKit
import Foundation

/// CloudKit-backed storage for sync state
@Observable
final class SyncStateCloudKitStore {
    static let shared = SyncStateCloudKitStore()

    private let container: CKContainer
    private let database: CKDatabase

    // Record type names
    private let syncMappingType = "SyncMapping"
    private let syncRecordType = "SyncRecord"
    private let syncHistoryType = "SyncHistory"

    private(set) var isAvailable = false
    private(set) var lastError: Error?

    private init() {
        container = CKContainer(identifier: "iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)")
        database = container.privateCloudDatabase
        checkAvailability()
    }

    // MARK: - Availability

    private func checkAvailability() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.isAvailable = status == .available
                self?.lastError = error
            }
        }
    }

    // MARK: - SyncMapping CRUD

    func saveSyncMapping(_ mapping: SyncMapping) async throws {
        let record = toCKRecord(mapping)
        _ = try await database.save(record)
    }

    func getSyncMappings() async throws -> [SyncMapping] {
        let query = CKQuery(recordType: syncMappingType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let (results, _) = try await database.records(matching: query)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return fromCKRecord(record) as SyncMapping?
        }
    }

    func getSyncMapping(id: UUID) async throws -> SyncMapping? {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        do {
            let record = try await database.record(for: recordID)
            return fromCKRecord(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func deleteSyncMapping(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        try await database.deleteRecord(withID: recordID)

        // Also delete all associated sync records
        try await deleteSyncRecords(forMappingId: id)
    }

    // MARK: - SyncRecord CRUD

    func saveSyncRecord(_ record: SyncRecord) async throws {
        let ckRecord = toCKRecord(record)
        _ = try await database.save(ckRecord)
    }

    func saveSyncRecords(_ records: [SyncRecord]) async throws {
        let ckRecords = records.map { toCKRecord($0) }

        let operation = CKModifyRecordsOperation(recordsToSave: ckRecords)
        operation.savePolicy = .allKeys

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    func getSyncRecords(forMappingId mappingId: UUID) async throws -> [SyncRecord] {
        let predicate = NSPredicate(format: "mappingId == %@", mappingId.uuidString)
        let query = CKQuery(recordType: syncRecordType, predicate: predicate)

        let (results, _) = try await database.records(matching: query)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return fromCKRecord(record) as SyncRecord?
        }
    }

    func getSyncRecord(appleReminderId: String, mappingId: UUID) async throws -> SyncRecord? {
        let predicate = NSPredicate(
            format: "mappingId == %@ AND appleReminderId == %@",
            mappingId.uuidString,
            appleReminderId
        )
        let query = CKQuery(recordType: syncRecordType, predicate: predicate)

        let (results, _) = try await database.records(matching: query)
        guard let first = results.first,
              case .success(let record) = first.1 else {
            return nil
        }
        return fromCKRecord(record)
    }

    func getSyncRecord(notionPageId: String, mappingId: UUID) async throws -> SyncRecord? {
        let predicate = NSPredicate(
            format: "mappingId == %@ AND notionPageId == %@",
            mappingId.uuidString,
            notionPageId
        )
        let query = CKQuery(recordType: syncRecordType, predicate: predicate)

        let (results, _) = try await database.records(matching: query)
        guard let first = results.first,
              case .success(let record) = first.1 else {
            return nil
        }
        return fromCKRecord(record)
    }

    func deleteSyncRecord(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        try await database.deleteRecord(withID: recordID)
    }

    func deleteSyncRecords(forMappingId mappingId: UUID) async throws {
        let records = try await getSyncRecords(forMappingId: mappingId)
        let recordIDs = records.map { CKRecord.ID(recordName: $0.id.uuidString) }

        guard !recordIDs.isEmpty else { return }

        let operation = CKModifyRecordsOperation(recordIDsToDelete: recordIDs)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    // MARK: - SyncHistory

    func saveSyncHistoryEntry(_ entry: SyncHistoryEntry) async throws {
        let record = toCKRecord(entry)
        _ = try await database.save(record)
    }

    func getSyncHistory(forMappingId mappingId: UUID, limit: Int = 50) async throws -> [SyncHistoryEntry] {
        let predicate = NSPredicate(format: "mappingId == %@", mappingId.uuidString)
        let query = CKQuery(recordType: syncHistoryType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        let (results, _) = try await database.records(matching: query, resultsLimit: limit)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return fromCKRecord(record) as SyncHistoryEntry?
        }
    }

    // MARK: - CKRecord Conversion - SyncMapping

    private func toCKRecord(_ mapping: SyncMapping) -> CKRecord {
        let record = CKRecord(recordType: syncMappingType, recordID: CKRecord.ID(recordName: mapping.id.uuidString))
        record["appleListId"] = mapping.appleListId
        record["appleListName"] = mapping.appleListName
        record["notionDatabaseId"] = mapping.notionDatabaseId
        record["notionDatabaseName"] = mapping.notionDatabaseName
        record["isEnabled"] = mapping.isEnabled ? 1 : 0
        record["lastSyncDate"] = mapping.lastSyncDate
        record["createdAt"] = mapping.createdAt
        record["titlePropertyId"] = mapping.titlePropertyId
        record["titlePropertyName"] = mapping.titlePropertyName
        record["dueDatePropertyId"] = mapping.dueDatePropertyId
        record["dueDatePropertyName"] = mapping.dueDatePropertyName
        record["priorityPropertyId"] = mapping.priorityPropertyId
        record["priorityPropertyName"] = mapping.priorityPropertyName
        record["statusPropertyId"] = mapping.statusPropertyId
        record["statusPropertyName"] = mapping.statusPropertyName
        record["statusCompletedValue"] = mapping.statusCompletedValue
        record["statusCompletedValues"] = mapping.statusCompletedValues
        record["completedPropertyId"] = mapping.completedPropertyId
        record["completedPropertyName"] = mapping.completedPropertyName
        return record
    }

    private func fromCKRecord(_ record: CKRecord) -> SyncMapping? {
        guard record.recordType == syncMappingType,
              let appleListId = record["appleListId"] as? String,
              let appleListName = record["appleListName"] as? String,
              let notionDatabaseId = record["notionDatabaseId"] as? String,
              let notionDatabaseName = record["notionDatabaseName"] as? String,
              let isEnabled = record["isEnabled"] as? Int,
              let createdAt = record["createdAt"] as? Date,
              let titlePropertyId = record["titlePropertyId"] as? String,
              let titlePropertyName = record["titlePropertyName"] as? String else {
            return nil
        }

        return SyncMapping(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            appleListId: appleListId,
            appleListName: appleListName,
            notionDatabaseId: notionDatabaseId,
            notionDatabaseName: notionDatabaseName,
            isEnabled: isEnabled != 0,
            lastSyncDate: record["lastSyncDate"] as? Date,
            createdAt: createdAt,
            titlePropertyId: titlePropertyId,
            titlePropertyName: titlePropertyName,
            dueDatePropertyId: record["dueDatePropertyId"] as? String,
            dueDatePropertyName: record["dueDatePropertyName"] as? String,
            priorityPropertyId: record["priorityPropertyId"] as? String,
            priorityPropertyName: record["priorityPropertyName"] as? String,
            statusPropertyId: record["statusPropertyId"] as? String,
            statusPropertyName: record["statusPropertyName"] as? String,
            statusCompletedValue: record["statusCompletedValue"] as? String,
            statusCompletedValues: record["statusCompletedValues"] as? [String],
            completedPropertyId: record["completedPropertyId"] as? String,
            completedPropertyName: record["completedPropertyName"] as? String
        )
    }

    // MARK: - CKRecord Conversion - SyncRecord

    private func toCKRecord(_ syncRecord: SyncRecord) -> CKRecord {
        let record = CKRecord(recordType: syncRecordType, recordID: CKRecord.ID(recordName: syncRecord.id.uuidString))
        record["mappingId"] = syncRecord.mappingId.uuidString
        record["appleReminderId"] = syncRecord.appleReminderId
        record["notionPageId"] = syncRecord.notionPageId
        record["lastSyncedHash"] = syncRecord.lastSyncedHash
        record["lastAppleModification"] = syncRecord.lastAppleModification
        record["lastNotionModification"] = syncRecord.lastNotionModification
        record["lastSyncDate"] = syncRecord.lastSyncDate
        record["syncStatus"] = syncRecord.syncStatus.rawValue
        return record
    }

    private func fromCKRecord(_ record: CKRecord) -> SyncRecord? {
        guard record.recordType == syncRecordType,
              let mappingIdString = record["mappingId"] as? String,
              let mappingId = UUID(uuidString: mappingIdString),
              let appleReminderId = record["appleReminderId"] as? String,
              let notionPageId = record["notionPageId"] as? String,
              let lastSyncedHash = record["lastSyncedHash"] as? String,
              let lastAppleModification = record["lastAppleModification"] as? Date,
              let lastNotionModification = record["lastNotionModification"] as? Date,
              let lastSyncDate = record["lastSyncDate"] as? Date,
              let syncStatusRaw = record["syncStatus"] as? String,
              let syncStatus = SyncRecord.SyncStatus(rawValue: syncStatusRaw) else {
            return nil
        }

        return SyncRecord(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
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

    // MARK: - CKRecord Conversion - SyncHistoryEntry

    private func toCKRecord(_ entry: SyncHistoryEntry) -> CKRecord {
        let record = CKRecord(recordType: syncHistoryType, recordID: CKRecord.ID(recordName: entry.id.uuidString))
        record["timestamp"] = entry.timestamp
        record["mappingId"] = entry.mappingId.uuidString
        record["operation"] = entry.operation.rawValue
        record["itemsCreated"] = entry.itemsCreated
        record["itemsUpdated"] = entry.itemsUpdated
        record["itemsDeleted"] = entry.itemsDeleted
        record["conflicts"] = entry.conflicts
        record["errors"] = entry.errors as [String]
        return record
    }

    private func fromCKRecord(_ record: CKRecord) -> SyncHistoryEntry? {
        guard record.recordType == syncHistoryType,
              let timestamp = record["timestamp"] as? Date,
              let mappingIdString = record["mappingId"] as? String,
              let mappingId = UUID(uuidString: mappingIdString),
              let operationRaw = record["operation"] as? String,
              let operation = SyncHistoryEntry.SyncOperation(rawValue: operationRaw),
              let itemsCreated = record["itemsCreated"] as? Int,
              let itemsUpdated = record["itemsUpdated"] as? Int,
              let itemsDeleted = record["itemsDeleted"] as? Int,
              let conflicts = record["conflicts"] as? Int else {
            return nil
        }

        return SyncHistoryEntry(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            timestamp: timestamp,
            mappingId: mappingId,
            operation: operation,
            itemsCreated: itemsCreated,
            itemsUpdated: itemsUpdated,
            itemsDeleted: itemsDeleted,
            conflicts: conflicts,
            errors: record["errors"] as? [String] ?? []
        )
    }
}
