import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let appState = AppState()
    private var statusBar: StatusBarController!
    private var poller: Poller!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(appState: appState)
        poller = Poller(appState: appState, interval: 300)
        Task { await poller.start() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        Task { await poller?.stop() }
    }
}
