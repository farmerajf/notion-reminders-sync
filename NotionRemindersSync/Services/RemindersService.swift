import EventKit
import Foundation

/// Service for interacting with Apple Reminders via EventKit
@Observable
final class RemindersService {
    static let shared = RemindersService()

    private let eventStore = EKEventStore()

    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    private func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async throws -> Bool {
        updateAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        case .denied, .restricted, .writeOnly:
            throw RemindersError.accessDenied
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToReminders()
            updateAuthorizationStatus()
            return granted
        @unknown default:
            throw RemindersError.unknownAuthorizationStatus
        }
    }

    // MARK: - Lists (Calendars)

    func getLists() -> [EKCalendar] {
        return eventStore.calendars(for: .reminder)
    }

    func getList(identifier: String) -> EKCalendar? {
        return eventStore.calendar(withIdentifier: identifier)
    }

    func getDefaultList() -> EKCalendar? {
        return eventStore.defaultCalendarForNewReminders()
    }

    // MARK: - Reminders - Read

    func getReminders(in list: EKCalendar) async throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [list])
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                }
            }
        }
    }

    func getReminder(identifier: String) -> EKReminder? {
        return eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
    }

    func getAllReminders() async throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: nil)
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                }
            }
        }
    }

    // MARK: - Reminders - Create

    func createReminder(from item: ReminderItem, in list: EKCalendar) throws -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        applyItemToReminder(item, reminder: reminder)

        try eventStore.save(reminder, commit: true)
        return reminder
    }

    // MARK: - Reminders - Update

    func updateReminder(_ reminder: EKReminder, with item: ReminderItem) throws {
        applyItemToReminder(item, reminder: reminder)
        try eventStore.save(reminder, commit: true)
    }

    /// Appends a short n:// URL to the reminder's notes if not already present.
    /// Returns true if the notes were updated, false if URL was already present.
    func appendNotionShortURLToNotes(identifier: String, shortId: String) throws -> Bool {
        guard let reminder = getReminder(identifier: identifier) else {
            throw RemindersError.reminderNotFound
        }

        let shortURL = "n://\(shortId)"

        // Check if this short URL already exists in the notes
        let currentNotes = reminder.notes ?? ""
        if currentNotes.contains(shortURL) {
            print("[RemindersService] Short URL already in notes for '\(reminder.title ?? "")'")
            return false
        }

        // Append the short URL to notes
        let separator = currentNotes.isEmpty ? "" : "\n\n"
        reminder.notes = currentNotes + separator + shortURL

        try eventStore.save(reminder, commit: true)
        print("[RemindersService] Appended short URL '\(shortURL)' to notes for '\(reminder.title ?? "")'")
        return true
    }

    // MARK: - Reminders - Delete

    func deleteReminder(_ reminder: EKReminder) throws {
        try eventStore.remove(reminder, commit: true)
    }

    func deleteReminder(identifier: String) throws {
        guard let reminder = getReminder(identifier: identifier) else {
            throw RemindersError.reminderNotFound
        }
        try deleteReminder(reminder)
    }

    // MARK: - Conversion

    func toReminderItem(_ reminder: EKReminder) -> ReminderItem {
        var dueDate: Date? = nil
        var hasDueTime = false

        if let dueDateComponents = reminder.dueDateComponents {
            dueDate = Calendar.current.date(from: dueDateComponents)
            hasDueTime = dueDateComponents.hour != nil
        }

        return ReminderItem(
            title: reminder.title ?? "",
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            priority: ReminderItem.Priority.fromApple(reminder.priority),
            isCompleted: reminder.isCompleted,
            modificationDate: reminder.lastModifiedDate ?? Date(),
            appleReminderId: reminder.calendarItemIdentifier
        )
    }

    // MARK: - Private Helpers

    private func applyItemToReminder(_ item: ReminderItem, reminder: EKReminder) {
        reminder.title = item.title
        reminder.priority = item.priority.appleValue
        reminder.isCompleted = item.isCompleted

        if let dueDate = item.dueDate {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: dueDate
            )

            if item.hasDueTime {
                let timeComponents = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: dueDate
                )
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
            }

            reminder.dueDateComponents = components
        } else {
            reminder.dueDateComponents = nil
        }
    }

    // MARK: - Errors

    enum RemindersError: LocalizedError {
        case accessDenied
        case unknownAuthorizationStatus
        case fetchFailed
        case reminderNotFound

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Access to Reminders was denied. Please grant access in System Settings."
            case .unknownAuthorizationStatus:
                return "Unknown authorization status for Reminders."
            case .fetchFailed:
                return "Failed to fetch reminders."
            case .reminderNotFound:
                return "Reminder not found."
            }
        }
    }
}
