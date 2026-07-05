import AppKit

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
        statusBar = StatusBarController(appState: appState, poller: poller)
        Task { await poller.start() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        AppLog.lifecycle.notice("App will terminate")
        Task { await poller.stop() }
    }
}
