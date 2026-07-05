import AppKit
import WebKit

@MainActor
public final class LoginWindowController: NSWindowController {
    private var webView: WKWebView!
    private var onFinish: (() -> Void)?

    public init(provider: any ProviderAdapter, onFinish: @escaping () -> Void) {
        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "登录 \(provider.displayName)"
        win.center()
        super.init(window: win)
        self.onFinish = onFinish

        AppLog.auth.notice("Login window opened for \(provider.displayName)")

        let config = WKWebViewConfiguration()
        // Use the default (persistent) website data store so cookies set during
        // login survive across app restarts. WebViewAdapter.fetch() uses the same
        // default store, and HTTPAdapter reads from it before making API calls.
        config.websiteDataStore = .default()
        self.webView = WKWebView(frame: win.contentView!.bounds, configuration: config)
        self.webView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(self.webView)
        self.webView.load(URLRequest(url: provider.loginURL))

        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                               name: NSWindow.willCloseNotification, object: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Show the window modelessly (we don't want a modal session blocking the menu-bar app).
    public func present() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()  // bring to front even if app is .accessory
    }

    @objc private func windowWillClose() {
        AppLog.auth.notice("Login window closed")
        onFinish?()
        onFinish = nil
    }
}
