import AppKit
import ServiceManagement

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let appState = AppState()
    public let poller: Poller
    private var statusBar: StatusBarController!

    override public init() {
        self.poller = Poller(appState: appState, interval: 300)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.lifecycle.notice("App did finish launching")
        // Sync launch-at-login preference with actual system state
        // (handles the case where the user changed it in System Settings)
        syncLaunchAtLoginStatus()
        statusBar = StatusBarController(appState: appState, poller: poller)
        Task { await poller.start() }
    }

    /// Update UserDefaults to reflect the current SMAppService registration status.
    private func syncLaunchAtLoginStatus() {
        let isRegistered = SMAppService.mainApp.status == .enabled
        if UserDefaults.standard.bool(forKey: "tb.launchAtLogin") != isRegistered {
            UserDefaults.standard.set(isRegistered, forKey: "tb.launchAtLogin")
            AppLog.lifecycle.debug("Launch-at-login synced: \(isRegistered)")
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        AppLog.lifecycle.notice("App will terminate")
        Task { await poller.stop() }
    }
}
