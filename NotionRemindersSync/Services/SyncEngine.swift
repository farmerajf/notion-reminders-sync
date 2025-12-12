import Foundation
import EventKit

/// Main sync orchestrator that coordinates syncing between Apple Reminders and Notion
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    private let remindersService = RemindersService.shared
    private let notionClient = NotionClient.shared
    private let syncStateStore = LocalSyncStateStore.shared
    private let conflictResolver = ConflictResolver()

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: Error?

    private init() {}

    // MARK: - Public Sync Methods

    /// Syncs all enabled mappings
    func syncAll() async throws {
        guard !isSyncing else {
            throw SyncError.alreadySyncing
        }

        isSyncing = true
        lastError = nil

        defer {
            isSyncing = false
        }

        let mappings = syncStateStore.getSyncMappings()
        let enabledMappings = mappings.filter { $0.isEnabled }

        print("[SyncEngine] Found \(mappings.count) mappings, \(enabledMappings.count) enabled")

        for mapping in enabledMappings {
            do {
                try await sync(mapping: mapping)
            } catch {
                print("[SyncEngine] Failed to sync mapping \(mapping.id): \(error)")
                lastError = error
                // Continue with other mappings
            }
        }

        lastSyncDate = Date()
    }

    /// Syncs a specific mapping
    func sync(mapping: SyncMapping) async throws {
        print("[SyncEngine] Starting sync for mapping: \(mapping.appleListName) <-> \(mapping.notionDatabaseName)")

        // 1. Fetch current state from both sources
        guard let appleList = remindersService.getList(identifier: mapping.appleListId) else {
            throw SyncError.appleListNotFound(mapping.appleListId)
        }

        let appleReminders = try await remindersService.getReminders(in: appleList)
        let notionPages = try await notionClient.getAllPages(in: mapping.notionDatabaseId)

        // 2. Convert to unified ReminderItem format
        let appleItems = appleReminders.map { remindersService.toReminderItem($0) }
        let notionItems = notionPages.map { toReminderItem($0, mapping: mapping) }

        // 3. Load existing sync records
        let syncRecords = syncStateStore.getSyncRecords(forMappingId: mapping.id)

        print("[SyncEngine] Found \(appleItems.count) Apple reminders, \(notionItems.count) Notion pages, \(syncRecords.count) sync records")

        // 4. Build lookup maps
        let appleItemsByReminderId = Dictionary(uniqueKeysWithValues: appleItems.compactMap { item -> (String, ReminderItem)? in
            guard let id = item.appleReminderId else { return nil }
            return (id, item)
        })

        let notionItemsByPageId = Dictionary(uniqueKeysWithValues: notionItems.compactMap { item -> (String, ReminderItem)? in
            guard let id = item.notionPageId else { return nil }
            return (id, item)
        })


        // 5. Determine sync actions for all items
        var actions: [(SyncAction, SyncRecord?)] = []
        var processedAppleIds = Set<String>()
        var processedNotionIds = Set<String>()

        // Process items that have been synced before (have sync records)
        for record in syncRecords {
            let appleItem = appleItemsByReminderId[record.appleReminderId]
            let notionItem = notionItemsByPageId[record.notionPageId]

            let action = determineSyncAction(
                appleItem: appleItem,
                notionItem: notionItem,
                syncRecord: record
            )

            actions.append((action, record))
            processedAppleIds.insert(record.appleReminderId)
            processedNotionIds.insert(record.notionPageId)
        }

        // Process new Apple items (no sync record = never synced before)
        for (appleId, appleItem) in appleItemsByReminderId where !processedAppleIds.contains(appleId) {
            // Check if there's a matching Notion item by title (first sync scenario)
            let matchingNotionItem = notionItems.first { $0.title == appleItem.title && $0.notionPageId != nil }

            if let notionItem = matchingNotionItem, let notionId = notionItem.notionPageId {
                // Found a match by title - decide which version to use
                if appleItem.modificationDate >= notionItem.modificationDate {
                    actions.append((.updateNotion(appleItem), nil))
                } else {
                    actions.append((.updateApple(notionItem), nil))
                }
                processedNotionIds.insert(notionId)
            } else {
                // New item in Apple only -> create in Notion
                actions.append((.createInNotion(appleItem), nil))
            }
        }

        // Process new Notion items (no sync record = never synced before)
        for (notionId, notionItem) in notionItemsByPageId where !processedNotionIds.contains(notionId) {
            // New item in Notion only -> create in Apple
            actions.append((.createInApple(notionItem), nil))
        }

        // 6. Execute actions
        var stats = SyncStats()

        for (action, existingRecord) in actions {
            do {
                try await execute(
                    action: action,
                    mapping: mapping,
                    appleList: appleList,
                    existingRecord: existingRecord,
                    stats: &stats
                )
            } catch {
                print("[SyncEngine] Action failed: \(error)")
                stats.errors.append(error.localizedDescription)
            }
        }

        // 7. Update mapping's last sync date
        var updatedMapping = mapping
        updatedMapping.lastSyncDate = Date()
        try syncStateStore.saveSyncMapping(updatedMapping)

        // 8. Save sync history
        let historyEntry = SyncHistoryEntry(
            mappingId: mapping.id,
            operation: .incrementalSync,
            itemsCreated: stats.created,
            itemsUpdated: stats.updated,
            itemsDeleted: stats.deleted,
            conflicts: stats.conflicts,
            errors: stats.errors
        )
        try syncStateStore.saveSyncHistoryEntry(historyEntry)

        print("[SyncEngine] Sync completed: \(stats.created) created, \(stats.updated) updated, \(stats.deleted) deleted, \(stats.conflicts) conflicts")
    }

    // MARK: - Sync Action Determination

    /// Determines what sync action to take for a previously-synced item.
    /// This is called when a SyncRecord exists, meaning the item was synced before.
    private func determineSyncAction(
        appleItem: ReminderItem?,
        notionItem: ReminderItem?,
        syncRecord: SyncRecord
    ) -> SyncAction {
        switch (appleItem, notionItem) {

        // Both exist: check if either changed, resolve conflicts if both changed
        case (.some(let apple), .some(let notion)):
            let resolution = conflictResolver.resolve(
                appleItem: apple,
                notionItem: notion,
                syncRecord: syncRecord
            )
            switch resolution {
            case .noChange:
                return .skip
            case .useApple(let item):
                return .updateNotion(item)
            case .useNotion(let item):
                return .updateApple(item)
            }

        // Only in Apple: was deleted from Notion -> propagate deletion
        case (.some(let apple), .none):
            return .deleteFromApple(apple)

        // Only in Notion: was deleted from Apple -> propagate deletion
        case (.none, .some(let notion)):
            return .deleteFromNotion(notion)

        // Both deleted: cleanup the sync record
        case (.none, .none):
            return .cleanupRecord
        }
    }

    // MARK: - Action Execution

    private func execute(
        action: SyncAction,
        mapping: SyncMapping,
        appleList: EKCalendar,
        existingRecord: SyncRecord?,
        stats: inout SyncStats
    ) async throws {
        switch action {
        case .createInNotion(let item):
            print("[SyncEngine] Creating in Notion: '\(item.title)' appleId=\(item.appleReminderId ?? "nil")")
            let page = try await createNotionPage(for: item, mapping: mapping)
            var newItem = item
            newItem.notionPageId = page.id
            print("[SyncEngine] After Notion create: appleId=\(newItem.appleReminderId ?? "nil") notionId=\(newItem.notionPageId ?? "nil")")
            try await saveSyncRecord(for: newItem, mapping: mapping, existingRecord: existingRecord)
            stats.created += 1

        case .createInApple(let item):
            print("[SyncEngine] Creating in Apple: '\(item.title)' notionId=\(item.notionPageId ?? "nil")")
            let reminder = try remindersService.createReminder(from: item, in: appleList)
            var newItem = item
            newItem.appleReminderId = reminder.calendarItemIdentifier
            print("[SyncEngine] After Apple create: appleId=\(newItem.appleReminderId ?? "nil") notionId=\(newItem.notionPageId ?? "nil")")
            try await saveSyncRecord(for: newItem, mapping: mapping, existingRecord: existingRecord)
            stats.created += 1

        case .updateNotion(let item):
            guard let pageId = item.notionPageId ?? existingRecord?.notionPageId else {
                throw SyncError.missingNotionPageId
            }
            try await updateNotionPage(pageId: pageId, with: item, mapping: mapping)
            try await saveSyncRecord(for: item, mapping: mapping, existingRecord: existingRecord)
            stats.updated += 1

        case .updateApple(let item):
            guard let reminderId = item.appleReminderId ?? existingRecord?.appleReminderId,
                  let reminder = remindersService.getReminder(identifier: reminderId) else {
                throw SyncError.missingAppleReminderId
            }
            try remindersService.updateReminder(reminder, with: item)
            try await saveSyncRecord(for: item, mapping: mapping, existingRecord: existingRecord)
            stats.updated += 1

        case .deleteFromNotion(let item):
            guard let pageId = item.notionPageId ?? existingRecord?.notionPageId else {
                throw SyncError.missingNotionPageId
            }
            _ = try await notionClient.archivePage(pageId: pageId)
            if let record = existingRecord {
                try syncStateStore.deleteSyncRecord(id: record.id)
            }
            stats.deleted += 1

        case .deleteFromApple(let item):
            guard let reminderId = item.appleReminderId ?? existingRecord?.appleReminderId else {
                throw SyncError.missingAppleReminderId
            }
            try remindersService.deleteReminder(identifier: reminderId)
            if let record = existingRecord {
                try syncStateStore.deleteSyncRecord(id: record.id)
            }
            stats.deleted += 1

        case .cleanupRecord:
            if let record = existingRecord {
                try syncStateStore.deleteSyncRecord(id: record.id)
            }

        case .skip:
            break
        }
    }

    private func createNotionPage(for item: ReminderItem, mapping: SyncMapping) async throws -> NotionPage {
        var properties: [String: NotionPropertyValue] = [:]

        // Title (required)
        properties[mapping.titlePropertyId] = .title([
            NotionPropertyValue.RichText(plainText: item.title)
        ])

        // Due date (optional)
        if let dueDatePropertyId = mapping.dueDatePropertyId, let dueDate = item.dueDate {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = item.hasDueTime ? [.withInternetDateTime] : [.withFullDate]
            let dateString = dateFormatter.string(from: dueDate)

            properties[dueDatePropertyId] = .date(
                NotionPropertyValue.DateValue(start: dateString)
            )
        }

        // Priority (optional)
        if let priorityPropertyId = mapping.priorityPropertyId, item.priority != .none {
            properties[priorityPropertyId] = .select(
                NotionPropertyValue.SelectValue(name: item.priority.notionValue)
            )
        }

        // Completed (optional)
        if let completedPropertyId = mapping.completedPropertyId {
            properties[completedPropertyId] = .checkbox(item.isCompleted)
        }

        return try await notionClient.createPage(in: mapping.notionDatabaseId, properties: properties)
    }

    private func updateNotionPage(pageId: String, with item: ReminderItem, mapping: SyncMapping) async throws {
        var properties: [String: NotionPropertyValue] = [:]

        // Title
        properties[mapping.titlePropertyId] = .title([
            NotionPropertyValue.RichText(plainText: item.title)
        ])

        // Due date
        if let dueDatePropertyId = mapping.dueDatePropertyId {
            if let dueDate = item.dueDate {
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = item.hasDueTime ? [.withInternetDateTime] : [.withFullDate]
                let dateString = dateFormatter.string(from: dueDate)
                properties[dueDatePropertyId] = .date(NotionPropertyValue.DateValue(start: dateString))
            } else {
                properties[dueDatePropertyId] = .date(nil)
            }
        }

        // Priority
        if let priorityPropertyId = mapping.priorityPropertyId {
            if item.priority != .none {
                properties[priorityPropertyId] = .select(
                    NotionPropertyValue.SelectValue(name: item.priority.notionValue)
                )
            } else {
                properties[priorityPropertyId] = .select(nil)
            }
        }

        // Completed
        if let completedPropertyId = mapping.completedPropertyId {
            properties[completedPropertyId] = .checkbox(item.isCompleted)
        }

        _ = try await notionClient.updatePage(pageId: pageId, properties: properties)
    }

    private func toReminderItem(_ page: NotionPage, mapping: SyncMapping) -> ReminderItem {
        // Extract title - use property NAME for lookups (Notion API returns properties keyed by name)
        var title = ""
        if let titleProp = page.properties[mapping.titlePropertyName] {
            title = titleProp.plainText ?? ""
        }

        // Extract due date
        var dueDate: Date? = nil
        var hasDueTime = false
        if let dueDatePropertyName = mapping.dueDatePropertyName,
           let dateProp = page.properties[dueDatePropertyName],
           let dateString = dateProp.dateStart {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                dueDate = date
                hasDueTime = dateString.contains("T")
            } else {
                // Try date-only format
                formatter.formatOptions = [.withFullDate]
                dueDate = formatter.date(from: dateString)
            }
        }

        // Extract priority
        var priority = ReminderItem.Priority.none
        if let priorityPropertyName = mapping.priorityPropertyName,
           let priorityProp = page.properties[priorityPropertyName],
           let priorityName = priorityProp.selectName {
            priority = ReminderItem.Priority.fromNotion(priorityName)
        }

        // Extract completed
        var isCompleted = false
        if let completedPropertyName = mapping.completedPropertyName,
           let completedProp = page.properties[completedPropertyName] {
            isCompleted = completedProp.isChecked
        }

        return ReminderItem(
            title: title,
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            priority: priority,
            isCompleted: isCompleted,
            modificationDate: page.lastEditedTime,
            notionPageId: page.id
        )
    }

    private func saveSyncRecord(
        for item: ReminderItem,
        mapping: SyncMapping,
        existingRecord: SyncRecord?
    ) async throws {
        guard let appleId = item.appleReminderId else {
            print("[SyncEngine] WARNING: Cannot save sync record - missing appleReminderId for '\(item.title)'")
            return
        }
        guard let notionId = item.notionPageId else {
            print("[SyncEngine] WARNING: Cannot save sync record - missing notionPageId for '\(item.title)'")
            return
        }

        let record = SyncRecord(
            id: existingRecord?.id ?? UUID(),
            mappingId: mapping.id,
            appleReminderId: appleId,
            notionPageId: notionId,
            lastSyncedHash: item.contentHash,
            lastAppleModification: item.modificationDate,
            lastNotionModification: item.modificationDate,
            syncStatus: .synced
        )

        try syncStateStore.saveSyncRecord(record)
        print("[SyncEngine] Saved sync record: Apple(\(appleId)) <-> Notion(\(notionId)) for '\(item.title)'")
    }

    // MARK: - Types

    private struct SyncStats {
        var created = 0
        var updated = 0
        var deleted = 0
        var conflicts = 0
        var errors: [String] = []
    }

    enum SyncError: LocalizedError {
        case alreadySyncing
        case appleListNotFound(String)
        case notionDatabaseNotFound(String)
        case missingAppleReminderId
        case missingNotionPageId

        var errorDescription: String? {
            switch self {
            case .alreadySyncing:
                return "A sync is already in progress"
            case .appleListNotFound(let id):
                return "Apple Reminders list not found: \(id)"
            case .notionDatabaseNotFound(let id):
                return "Notion database not found: \(id)"
            case .missingAppleReminderId:
                return "Missing Apple Reminder ID"
            case .missingNotionPageId:
                return "Missing Notion page ID"
            }
        }
    }
}
