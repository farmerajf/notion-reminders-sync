import Foundation

/// Unified reminder representation for both Apple Reminders and Notion
struct ReminderItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var dueDate: Date?
    var hasDueTime: Bool
    var priority: Priority
    var isCompleted: Bool
    var modificationDate: Date

    // Source identifiers
    var appleReminderId: String?
    var notionPageId: String?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        priority: Priority = .none,
        isCompleted: Bool = false,
        modificationDate: Date = Date(),
        appleReminderId: String? = nil,
        notionPageId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.modificationDate = modificationDate
        self.appleReminderId = appleReminderId
        self.notionPageId = notionPageId
    }

    /// Computes a hash of the content for change detection
    var contentHash: String {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(dueDate)
        hasher.combine(hasDueTime)
        hasher.combine(priority)
        hasher.combine(isCompleted)
        return String(hasher.finalize())
    }
}

// MARK: - Priority
extension ReminderItem {
    enum Priority: Int, Codable, CaseIterable, Hashable {
        case none = 0
        case low = 9
        case medium = 5
        case high = 1

        /// Maps to Notion select property value
        var notionValue: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        /// Creates from Notion select value
        static func fromNotion(_ value: String) -> Priority {
            switch value.lowercased() {
            case "low": return .low
            case "medium": return .medium
            case "high": return .high
            default: return .none
            }
        }

        /// Creates from Apple Reminders priority (0-9, where 0 is none, 1 is high, 9 is low)
        static func fromApple(_ value: Int) -> Priority {
            switch value {
            case 0: return .none
            case 1...3: return .high
            case 4...6: return .medium
            case 7...9: return .low
            default: return .none
            }
        }

        /// Apple Reminders priority value
        var appleValue: Int {
            self.rawValue
        }

        var displayName: String {
            notionValue
        }
    }
}
