import Foundation
import WebKit

/// Base class for any provider whose quota can only be read from a
/// browser session (i.e. requires a logged-in cookie set). Loads the
/// `loginURL` in an off-screen `WKWebView`, then on `didFinish` evaluates
/// `harvestScript` — the returned value is parsed by the subclass.
///
/// Subclasses override `parse(harvest:)` to convert the JavaScript result
/// into a `Snapshot`.
public class WebViewAdapter: NSObject, ProviderAdapter, WKNavigationDelegate {
    public let id: String
    public let displayName: String
    public let iconSystemName: String
    public let loginURL: URL
    public let harvestScript: String

    /// Strong reference to the live WKWebView during a fetch; nil between calls.
    /// Without this, the WKWebView would be deallocated before `didFinish` fires.
    private var currentWebView: WKWebView?
    private var continuation: CheckedContinuation<Snapshot, Never>?

    public init(id: String, displayName: String, iconSystemName: String,
                loginURL: URL, harvestScript: String) {
        self.id = id; self.displayName = displayName; self.iconSystemName = iconSystemName
        self.loginURL = loginURL; self.harvestScript = harvestScript
    }

    public func fetch() async -> Snapshot {
        await withCheckedContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 800), configuration: config)
            self.currentWebView = webView
            webView.navigationDelegate = self
            webView.load(URLRequest(url: loginURL))
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(harvestScript) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.continuation?.resume(returning: Snapshot(providerId: self.id, quotas: [],
                    status: .error("js: \(error.localizedDescription)")))
                self.cleanup(); return
            }
            let snap = self.parse(harvest: result)
            self.continuation?.resume(returning: snap)
            self.cleanup()
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: Snapshot(providerId: id, quotas: [],
            status: .error("nav: \(error.localizedDescription)")))
        cleanup()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func cleanup() {
        continuation = nil
        currentWebView?.loadHTMLString("", baseURL: nil)  // cancel pending
        currentWebView = nil
    }

    /// Subclasses parse the JS harvest into a Snapshot.
    public func parse(harvest: Any?) -> Snapshot { fatalError("override") }
}
