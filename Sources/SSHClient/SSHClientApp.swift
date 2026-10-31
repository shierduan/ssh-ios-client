import SwiftUI
import SwiftData

@main
struct SSHClientApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Host.self, HostGroup.self, SSHKey.self, CommandSnippet.self
        ])
        let configuration = ModelConfiguration("SSHClient", schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("无法初始化 SwiftData 容器: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

/// 负责后台任务与全局生命周期钩子(参考 pockterm/iOSSH:切后台时保持 SSH 短暂活跃)。
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundTask = application.beginBackgroundTask(withName: "SSHKeepAlive") {
            application.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        if backgroundTask != .invalid {
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
