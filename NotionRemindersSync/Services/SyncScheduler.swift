import Foundation
import Combine

/// Schedules and manages periodic sync operations
@Observable
final class SyncScheduler {
    static let shared = SyncScheduler()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private(set) var isRunning = false
    private(set) var nextSyncDate: Date?

    private let syncEngine: SyncEngine

    @ObservationIgnored
    private var syncIntervalMinutes: Int {
        UserDefaults.standard.integer(forKey: "syncIntervalMinutes").nonZeroOr(5)
    }

    private init() {
        syncEngine = SyncEngine.shared

        // Observe changes to sync interval
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                if self?.isRunning == true {
                    self?.restart()
                }
            }
            .store(in: &cancellables)
    }

    /// Starts the sync scheduler
    func start() {
        guard !isRunning else { return }

        isRunning = true
        scheduleNextSync()

        print("[SyncScheduler] Started with interval: \(syncIntervalMinutes) minutes")
    }

    /// Stops the sync scheduler
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        nextSyncDate = nil

        print("[SyncScheduler] Stopped")
    }

    /// Restarts the scheduler with current settings
    func restart() {
        stop()
        start()
    }

    /// Triggers an immediate sync
    func syncNow() async {
        await performSync()

        // Reschedule if running
        if isRunning {
            scheduleNextSync()
        }
    }

    // MARK: - Private

    private func scheduleNextSync() {
        timer?.invalidate()

        let interval = TimeInterval(syncIntervalMinutes * 60)
        nextSyncDate = Date().addingTimeInterval(interval)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performSync()
                self?.scheduleNextSync()
            }
        }
    }

    private func performSync() async {
        do {
            print("[SyncScheduler] Starting sync...")
            try await syncEngine.syncAll()
            print("[SyncScheduler] Sync completed successfully")
        } catch {
            print("[SyncScheduler] Sync failed: \(error)")
        }
    }
}

// MARK: - Helper Extension

private extension Int {
    func nonZeroOr(_ defaultValue: Int) -> Int {
        self == 0 ? defaultValue : self
    }
}
