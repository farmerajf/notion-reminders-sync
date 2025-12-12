import Foundation

/// Resolves conflicts when the same item was modified on both sides since last sync.
/// Uses "most recent wins" strategy.
struct ConflictResolver {

    enum Resolution {
        case useApple(ReminderItem)   // Apple version wins
        case useNotion(ReminderItem)  // Notion version wins
        case noChange                  // Content is identical, no action needed
    }

    /// Resolves a conflict between two versions of the same item.
    /// Only call this when both items exist and have been previously synced.
    func resolve(
        appleItem: ReminderItem,
        notionItem: ReminderItem,
        syncRecord: SyncRecord
    ) -> Resolution {
        // Check if content is identical - no sync needed
        if appleItem.contentHash == notionItem.contentHash {
            return .noChange
        }

        // Determine which side changed since last sync
        let appleChanged = appleItem.contentHash != syncRecord.lastSyncedHash
        let notionChanged = notionItem.modificationDate > syncRecord.lastNotionModification

        // If only one side changed, use that side (no conflict)
        if appleChanged && !notionChanged {
            return .useApple(appleItem)
        }
        if notionChanged && !appleChanged {
            return .useNotion(notionItem)
        }

        // Both changed - true conflict, most recent wins
        if appleItem.modificationDate >= notionItem.modificationDate {
            return .useApple(appleItem)
        } else {
            return .useNotion(notionItem)
        }
    }
}

/// Action to take during sync
enum SyncAction {
    case createInNotion(ReminderItem)
    case createInApple(ReminderItem)
    case updateNotion(ReminderItem)
    case updateApple(ReminderItem)
    case deleteFromNotion(ReminderItem)
    case deleteFromApple(ReminderItem)
    case cleanupRecord
    case skip
}
