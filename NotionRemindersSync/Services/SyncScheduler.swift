import Foundation
import Combine
import UIKit

/// Schedules and manages periodic sync operations
@Observable
final class SyncScheduler {
    static let shared = SyncScheduler()

    private var timer: Timer?
    private(set) var isRunning = false
    private(set) var nextSyncDate: Date?

    private let syncEngine: SyncEngine

    @ObservationIgnored
    private let syncIntervalMinutes = 5

    private init() {
        syncEngine = SyncEngine.shared
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

        let newTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performSync()
                self?.scheduleNextSync()
            }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func performSync() async {
        do {
            print("[SyncScheduler] Starting sync...")
            try await syncEngine.syncAll()
            print("[SyncScheduler] Sync completed successfully")
            scheduleBackgroundRefreshIfNeeded()
        } catch {
            print("[SyncScheduler] Sync failed: \(error)")
        }
    }

    private func scheduleBackgroundRefreshIfNeeded() {
        // Schedule background refresh when app enters background
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.scheduleBackgroundTasks()
        }
    }
}
