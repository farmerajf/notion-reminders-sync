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
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        print("[AppDelegate] Registered background task: \(Self.backgroundTaskIdentifier)")

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundProcessingIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundProcessing(task: task as! BGProcessingTask)
        }
        print("[AppDelegate] Registered background task: \(Self.backgroundProcessingIdentifier)")
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        print("[AppDelegate] Handling background refresh")

        // Schedule the next refresh
        scheduleBackgroundRefresh()

        // Create sync task
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

        // Handle task expiration
        task.expirationHandler = {
            print("[AppDelegate] Background task expired")
            syncTask.cancel()
        }
    }

    private func handleBackgroundProcessing(task: BGProcessingTask) {
        print("[AppDelegate] Handling background processing")

        // Schedule the next processing task
        scheduleBackgroundProcessing()

        let syncTask = Task {
            do {
                try await SyncEngine.shared.syncAll()
                print("[AppDelegate] Background processing sync completed successfully")
                task.setTaskCompleted(success: true)
            } catch {
                print("[AppDelegate] Background processing sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            print("[AppDelegate] Background processing task expired")
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
