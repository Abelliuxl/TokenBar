import AppKit
import WebKit

@MainActor
public final class LoginWindowController: NSWindowController {
    private var webView: WKWebView!
    private var onFinish: ((Data?) -> Void)?

    public init(provider: any ProviderAdapter, onFinish: @escaping (Data?) -> Void) {
        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "登录 \(provider.displayName)"
        win.center()
        super.init(window: win)
        self.onFinish = onFinish

        let config = WKWebViewConfiguration()
        // Use the default (persistent) website data store so cookies set during
        // login survive across app restarts. WebViewAdapter.fetch() uses the same
        // default store, so logged-in cookies are picked up on the next poll.
        // (For HTTP adapters we additionally mirror cookies into the Keychain.)
        config.websiteDataStore = .default()
        self.webView = WKWebView(frame: win.contentView!.bounds, configuration: config)
        self.webView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(self.webView)
        self.webView.load(URLRequest(url: provider.loginURL))

        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                               name: NSWindow.willCloseNotification, object: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Show the window modelessly (we don't want a modal session blocking the menu-bar app).
    public func present() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()  // bring to front even if app is .accessory
    }

    @objc private func windowWillClose() {
        // Harvest cookies from the login webview's persistent store.
        // Domain match: cookie.domain must equal host or be a parent of host
        // (correct suffix direction; the previous `contains()` matched too loosely
        // — e.g. "b.foo.com" against host "foo.com.b" would have matched).
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] all in
            let host = self?.webView.url?.host ?? ""
            let relevant = all.filter { cookie in
                let cd = cookie.domain
                return cd == host || host.hasSuffix(".\(cd)")
            }
            let json = Self.serialize(cookies: relevant)
            DispatchQueue.main.async {
                self?.onFinish?(json)
                self?.onFinish = nil
            }
        }
    }

    private static func serialize(cookies: [HTTPCookie]) -> Data? {
        let arr = cookies.map { ["name": $0.name, "value": $0.value, "domain": $0.domain] }
        return try? JSONSerialization.data(withJSONObject: arr, options: [])
    }
}