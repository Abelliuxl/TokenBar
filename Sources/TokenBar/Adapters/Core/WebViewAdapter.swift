import Foundation
import WebKit
import Dispatch

/// Base class for any provider whose quota can only be read from a
/// browser session (i.e. requires a logged-in cookie set). Loads the
/// `loginURL` in an off-screen `WKWebView`, then on `didFinish` evaluates
/// `harvestScript` — the returned value is parsed by the subclass.
///
/// Subclasses override `parse(harvest:)` to convert the JavaScript result
/// into a `Snapshot`.
///
/// - Important: WKWebView must be used on the main actor. `fetch()` hops
///   to `MainActor` internally via `MainActor.run` before creating the
///   WebView. Navigation delegate callbacks are inherently on the main thread.
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
    private var didEvaluate = false
    private var pendingEvaluation: DispatchWorkItem?
    private var timeout: DispatchWorkItem?

    public init(id: String, displayName: String, iconSystemName: String,
                loginURL: URL, harvestScript: String) {
        self.id = id; self.displayName = displayName; self.iconSystemName = iconSystemName
        self.loginURL = loginURL; self.harvestScript = harvestScript
    }

    public func fetch() async -> Snapshot {
        AppLog.network.debug("[\(self.id)] WebView loading \(self.loginURL.absoluteString)")
        return await withCheckedContinuation { cont in
            // WKWebView APIs must run on the main thread. If we're already
            // there (e.g. called from MainActor), just proceed; otherwise
            // hop via sync dispatch (safe because setup is instant).
            let setup = {
                guard self.continuation == nil else {
                    cont.resume(returning: Snapshot(providerId: self.id, quotas: [], status: .error("fetch already in progress")))
                    return
                }
                self.continuation = cont
                self.didEvaluate = false
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .default()
                let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                self.currentWebView = webView
                webView.navigationDelegate = self
                self.scheduleTimeout()
                webView.load(URLRequest(url: self.loginURL))
            }
            if Thread.isMainThread { setup() }
            else { DispatchQueue.main.sync(execute: setup) }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didEvaluate else { return }
        pendingEvaluation?.cancel()
        AppLog.network.debug("[\(self.id)] Page navigation finished at \(webView.url?.absoluteString ?? "<nil>"), waiting for idle")
        let item = DispatchWorkItem { [weak self, weak webView] in
            guard let self, let webView else { return }
            guard !self.didEvaluate else { return }
            self.didEvaluate = true
            self.evaluateHarvestScript(in: webView)
        }
        pendingEvaluation = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
    }

    private func evaluateHarvestScript(in webView: WKWebView) {
        webView.evaluateJavaScript(harvestScript) { [weak self] result, error in
            guard let self else { return }
            if let error {
                AppLog.network.warning("[\(self.id)] JS harvest error: \(error.localizedDescription)")
                self.finish(Snapshot(providerId: self.id, quotas: [],
                    status: .error("js: \(error.localizedDescription)")))
                return
            }
            AppLog.network.debug("[\(self.id)] JS harvest succeeded")
            let snap = self.parse(harvest: result)
            self.finish(snap)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        AppLog.network.error("[\(self.id)] Navigation failed: \(error.localizedDescription)")
        finish(Snapshot(providerId: id, quotas: [],
            status: .error("nav: \(error.localizedDescription)")))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func scheduleTimeout() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(Snapshot(providerId: self.id, quotas: [], status: .error("timeout")))
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)
    }

    private func finish(_ snapshot: Snapshot) {
        guard let continuation else { return }
        cleanup()
        continuation.resume(returning: snapshot)
    }

    private func cleanup() {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        timeout?.cancel()
        timeout = nil
        currentWebView?.navigationDelegate = nil
        currentWebView?.stopLoading()
        continuation = nil
        currentWebView = nil
    }

    /// Subclasses parse the JS harvest into a Snapshot.
    public func parse(harvest: Any?) -> Snapshot { fatalError("override") }
}
