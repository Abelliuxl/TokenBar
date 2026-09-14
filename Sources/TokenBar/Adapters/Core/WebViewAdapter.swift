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
    public let brandIcon: BrandIcon?
    public let loginURL: URL
    public let harvestScript: String

    /// Strong reference to the live WKWebView during a fetch; nil between calls.
    /// Without this, the WKWebView would be deallocated before `didFinish` fires.
    private var currentWebView: WKWebView?
    private var continuation: CheckedContinuation<Snapshot, Never>?
    private var didEvaluate = false
    private var harvestAttempt = 0
    private var pendingEvaluation: DispatchWorkItem?
    private var pendingNavigationRetry: DispatchWorkItem?
    private var navigationAttempt = 0
    private var currentNavigation: WKNavigation?
    private var timeout: DispatchWorkItem?

    public init(id: String, displayName: String, iconSystemName: String,
                loginURL: URL, harvestScript: String, brandIcon: BrandIcon? = nil) {
        self.id = id; self.displayName = displayName; self.iconSystemName = iconSystemName
        self.loginURL = loginURL; self.harvestScript = harvestScript
        self.brandIcon = brandIcon
    }

    public func fetch() async -> Snapshot {
        AppLog.network.debug("[\(self.id)] WebView loading \(self.loginURL.absoluteString)")
        DiagnosticLog.record("webview", "provider=\(id) fetch requested url=\(DiagnosticLog.safeURL(loginURL.absoluteString))")
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
                self.harvestAttempt = 0
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .default()
                let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                self.currentWebView = webView
                DiagnosticLog.record("webview", "provider=\(self.id) created")
                webView.navigationDelegate = self
                self.navigationAttempt = 0
                self.startNavigation()
            }
            if Thread.isMainThread { setup() }
            else { DispatchQueue.main.sync(execute: setup) }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        AppLog.network.debug("[\(self.id)] Page navigation finished at \(webView.url?.absoluteString ?? "<nil>"), waiting for idle")
        scheduleHarvest(in: webView, reason: "navigation finished")
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        guard harvestOnNavigationCommit else { return }
        AppLog.network.debug("[\(self.id)] Page committed at \(webView.url?.absoluteString ?? "<nil>"), starting readiness polling")
        scheduleHarvest(in: webView, reason: "navigation committed")
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        didEvaluate = false
    }

    private func startNavigation() {
        guard continuation != nil, let webView = currentWebView else { return }
        navigationAttempt += 1
        didEvaluate = false
        harvestAttempt = 0
        scheduleTimeout()

        var request = URLRequest(
            url: loginURL,
            cachePolicy: navigationRequestCachePolicy,
            timeoutInterval: navigationTimeout
        )
        for (field, value) in navigationRequestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        DiagnosticLog.record(
            "webview",
            "provider=\(id) navigation attempt=\(navigationAttempt)/\(maximumNavigationAttempts) cachePolicy=\(navigationRequestCachePolicy.rawValue)"
        )
        currentNavigation = webView.load(request)
    }

    private func scheduleHarvest(in webView: WKWebView, reason: String) {
        guard continuation != nil, !didEvaluate, pendingEvaluation == nil else { return }
        DiagnosticLog.record(
            "webview",
            "provider=\(id) \(reason) waiting=\(harvestDelay)s"
        )
        let item = DispatchWorkItem { [weak self, weak webView] in
            guard let self, let webView else { return }
            guard self.continuation != nil, !self.didEvaluate else { return }
            self.pendingEvaluation = nil
            self.didEvaluate = true
            self.evaluateHarvestScript(in: webView)
        }
        pendingEvaluation = item
        DispatchQueue.main.asyncAfter(deadline: .now() + harvestDelay, execute: item)
    }

    private func evaluateHarvestScript(in webView: WKWebView) {
        harvestAttempt += 1
        webView.evaluateJavaScript(harvestScript) { [weak self] result, error in
            guard let self else { return }
            if let error {
                AppLog.network.warning("[\(self.id)] JS harvest error: \(error.localizedDescription)")
                DiagnosticLog.record("webview", "provider=\(self.id) javascript failed error=\(error.localizedDescription)")
                self.finish(Snapshot(providerId: self.id, quotas: [],
                    status: .error("js: \(error.localizedDescription)")))
                return
            }
            AppLog.network.debug("[\(self.id)] JS harvest succeeded")
            DiagnosticLog.record("webview", "provider=\(self.id) javascript completed resultType=\(String(describing: type(of: result)))")
            if self.shouldRetry(harvest: result), self.harvestAttempt < self.maximumHarvestAttempts {
                let attempt = self.harvestAttempt
                self.didEvaluate = false
                DiagnosticLog.record("webview", "provider=\(self.id) target not ready; retry=\(attempt)/\(self.maximumHarvestAttempts) in \(self.harvestRetryDelay)s")
                let item = DispatchWorkItem { [weak self, weak webView] in
                    guard let self, let webView, self.continuation != nil else { return }
                    self.pendingEvaluation = nil
                    self.didEvaluate = true
                    self.evaluateHarvestScript(in: webView)
                }
                self.pendingEvaluation = item
                DispatchQueue.main.asyncAfter(deadline: .now() + self.harvestRetryDelay, execute: item)
                return
            }
            let snap = self.parse(harvest: result)
            self.finish(snap)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === currentNavigation else { return }
        if retryNavigation(reason: "navigation failed: \(error.localizedDescription)") {
            return
        }
        AppLog.network.error("[\(self.id)] Navigation failed: \(error.localizedDescription)")
        DiagnosticLog.record("webview", "provider=\(id) navigation failed url=\(DiagnosticLog.safeURL(webView.url?.absoluteString)) error=\(error.localizedDescription)")
        finish(Snapshot(providerId: id, quotas: [],
            status: .error("nav: \(error.localizedDescription)")))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func scheduleTimeout() {
        timeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.retryNavigation(reason: "timeout") {
                return
            }
            DiagnosticLog.record("webview", "provider=\(self.id) timed out after \(self.navigationTimeout)s url=\(DiagnosticLog.safeURL(self.currentWebView?.url?.absoluteString))")
            self.finish(Snapshot(providerId: self.id, quotas: [], status: .error("timeout")))
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationTimeout, execute: item)
    }

    private func retryNavigation(reason: String) -> Bool {
        guard continuation != nil, currentWebView != nil else {
            return false
        }
        if pendingNavigationRetry != nil { return true }
        guard navigationAttempt < maximumNavigationAttempts else { return false }

        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        currentWebView?.stopLoading()
        didEvaluate = false
        harvestAttempt = 0
        let nextAttempt = navigationAttempt + 1
        DiagnosticLog.record(
            "webview",
            "provider=\(id) \(reason); retrying navigation attempt=\(nextAttempt)/\(maximumNavigationAttempts) in \(navigationRetryDelay)s"
        )
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.continuation != nil else { return }
            self.pendingNavigationRetry = nil
            self.startNavigation()
        }
        pendingNavigationRetry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationRetryDelay, execute: item)
        return true
    }

    private func finish(_ snapshot: Snapshot) {
        guard let continuation else { return }
        cleanup()
        continuation.resume(returning: snapshot)
    }

    private func cleanup() {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        pendingNavigationRetry?.cancel()
        pendingNavigationRetry = nil
        timeout?.cancel()
        timeout = nil
        currentWebView?.navigationDelegate = nil
        currentWebView?.stopLoading()
        currentNavigation = nil
        continuation = nil
        currentWebView = nil
    }

    /// Subclasses parse the JS harvest into a Snapshot.
    public func parse(harvest: Any?) -> Snapshot { fatalError("override") }

    /// Subclasses for asynchronously rendered pages can opt into repeated harvests.
    public var maximumHarvestAttempts: Int { 1 }
    public var harvestRetryDelay: TimeInterval { 1 }
    public func shouldRetry(harvest: Any?) -> Bool { false }
    public var navigationTimeout: TimeInterval { 45 }
    public var maximumNavigationAttempts: Int { 1 }
    public var navigationRetryDelay: TimeInterval { 1 }
    public var harvestDelay: TimeInterval { 3 }
    public var harvestOnNavigationCommit: Bool { false }
    public var navigationRequestCachePolicy: URLRequest.CachePolicy { .useProtocolCachePolicy }
    public var navigationRequestHeaders: [String: String] { [:] }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        DiagnosticLog.record("webview", "provider=\(id) web content process terminated url=\(DiagnosticLog.safeURL(webView.url?.absoluteString))")
        finish(Snapshot(providerId: id, quotas: [], status: .error("网页进程已终止")))
    }
}
