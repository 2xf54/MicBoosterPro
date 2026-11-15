import BackgroundTasks
import SwiftUI
import UserNotifications

final class RorAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct RorApp: App {
    @UIApplicationDelegateAdaptor(RorAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = RorViewModel()

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.ghazi.ror.sync", using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleBackgroundSync(refreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        vm.syncFromPC(silent: true)
                    } else if phase == .background {
                        Self.scheduleBackgroundSync()
                    }
                }
        }
    }

    static func scheduleBackgroundSync() {
        guard RorConfigStore.isPaired else { return }
        let request = BGAppRefreshTaskRequest(identifier: "com.ghazi.ror.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleBackgroundSync(_ task: BGAppRefreshTask) {
        scheduleBackgroundSync()
        let syncWork = Task {
            let ok = await RorViewModel.performBackgroundSync()
            task.setTaskCompleted(success: ok)
        }
        task.expirationHandler = {
            syncWork.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
