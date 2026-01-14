import UIKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    static let backgroundTaskIdentifier = "dev.adamfarmer.notionremindersync.refresh"
    static let backgroundProcessingIdentifier = "dev.adamfarmer.notionremindersync.processing"

    private let syncScheduler = SyncScheduler.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        syncScheduler.start()
        scheduleBackgroundTasks()
        print("[AppDelegate] App launched, sync scheduler started")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundTasks()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        syncScheduler.start()
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task, scheduleNext: self.scheduleBackgroundRefresh)
        }
        print("[AppDelegate] Registered background task: \(Self.backgroundTaskIdentifier)")

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundProcessingIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task, scheduleNext: self.scheduleBackgroundProcessing)
        }
        print("[AppDelegate] Registered background task: \(Self.backgroundProcessingIdentifier)")
    }

    private func handleBackgroundTask(_ task: BGTask, scheduleNext: @escaping () -> Void) {
        print("[AppDelegate] Handling background task: \(task.identifier)")
        scheduleNext()

        let syncTask = Task {
            do {
                try await SyncEngine.shared.syncAll()
                print("[AppDelegate] Background sync completed successfully")
                task.setTaskCompleted(success: true)
            } catch {
                print("[AppDelegate] Background sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            print("[AppDelegate] Background task expired")
            syncTask.cancel()
        }
    }

    func scheduleBackgroundTasks() {
        scheduleBackgroundRefresh()
        scheduleBackgroundProcessing()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run at least 15 minutes from now (iOS minimum)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[AppDelegate] Scheduled background refresh for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            print("[AppDelegate] Failed to schedule background refresh: \(error)")
        }
    }

    func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[AppDelegate] Scheduled background processing for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            print("[AppDelegate] Failed to schedule background processing: \(error)")
        }
    }
}
