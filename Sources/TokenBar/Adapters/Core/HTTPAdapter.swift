import Foundation
import WebKit

/// Concrete `ProviderAdapter` that performs a single HTTP request (GET/POST),
/// inside WebKit's persistent browser context and feeds the response body to a
/// caller-supplied decoder closure.
///
/// Concrete adapters (e.g. `SiliconFlowAdapter`) typically compose this with
/// their own thin wrapper struct that supplies `id` / `displayName` / etc.,
/// rather than subclassing — keeps this type `final` and `Sendable`.
public final class HTTPAdapter: ProviderAdapter {
    public let id: String
    public let displayName: String
    public let iconSystemName: String
    public let loginURL: URL
    public let method: String
    public let url: URL
    public let headers: [String: String]
    private let decoder: @Sendable (Data) -> Snapshot
    private let pageFallbackDecoder: (@Sendable (BrowserPageContext) -> Snapshot?)?

    public init(id: String,
                displayName: String,
                iconSystemName: String,
                loginURL: URL,
                method: String,
                url: URL,
                headers: [String: String] = [:],
                pageFallbackDecoder: (@Sendable (BrowserPageContext) -> Snapshot?)? = nil,
                decoder: @escaping @Sendable (Data) -> Snapshot) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.loginURL = loginURL
        self.method = method
        self.url = url
        self.headers = headers
        self.pageFallbackDecoder = pageFallbackDecoder
        self.decoder = decoder
    }

    public func fetch() async -> Snapshot {
        AppLog.network.debug("[\(self.id)] browser fetch \(self.url.absoluteString)")
        switch await browserFetch() {
        case .success(let status, let data, let page):
            if status == 401 || status == 403 || Self.looksLikeLoginURL(page.url) {
                AppLog.network.warning("[\(self.id)] browser fetch auth failure HTTP \(status), finalURL \(page.url)")
                return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
            }
            guard (200..<300).contains(status) else {
                if let fallback = pageFallbackDecoder?(page) {
                    AppLog.network.notice("[\(self.id)] API HTTP \(status), using page fallback")
                    return fallback
                }
                let preview = DiagnosticPreview.from(data)
                AppLog.network.warning("[\(self.id)] browser fetch HTTP \(status): \(preview)")
                return Snapshot(providerId: id, quotas: [], status: .error("HTTP \(status): \(preview)"))
            }
            AppLog.network.debug("[\(self.id)] browser fetch HTTP \(status) → \(data.count) bytes")
            let decoded = decoder(data)
            if case .error = decoded.status, let fallback = pageFallbackDecoder?(page) {
                AppLog.network.notice("[\(self.id)] API decode failed, using page fallback")
                return fallback
            }
            return decoded
        case .failure(let message):
            AppLog.network.error("[\(self.id)] browser fetch failed: \(message)")
            return Snapshot(providerId: id, quotas: [], status: .error(message))
        }
    }

    private func browserFetch() async -> BrowserFetchResult {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let session = BrowserFetchSession(
                    id: id,
                    loginURL: loginURL,
                    targetURL: url,
                    method: method,
                    headers: headers
                ) { result in
                    continuation.resume(returning: result)
                }
                session.start()
            }
        }
    }

    private static func looksLikeLoginURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("/login") || lower.contains("/signin") || lower.contains("/auth")
    }
}

public struct BrowserPageContext: Sendable {
    public let url: String
    public let title: String
    public let text: String
}

private enum BrowserFetchResult: Sendable {
    case success(status: Int, data: Data, page: BrowserPageContext)
    case failure(String)
}

@MainActor
private final class BrowserFetchSession: NSObject, WKNavigationDelegate {
    private let id: String
    private let loginURL: URL
    private let targetURL: URL
    private let method: String
    private let headers: [String: String]
    private let completion: (BrowserFetchResult) -> Void
    private var webView: WKWebView?
    private var retainedSelf: BrowserFetchSession?
    private var timeout: DispatchWorkItem?
    private var pendingEvaluation: DispatchWorkItem?
    private var didEvaluate = false

    init(id: String,
         loginURL: URL,
         targetURL: URL,
         method: String,
         headers: [String: String],
         completion: @escaping (BrowserFetchResult) -> Void) {
        self.id = id
        self.loginURL = loginURL
        self.targetURL = targetURL
        self.method = method
        self.headers = headers
        self.completion = completion
    }

    func start() {
        retainedSelf = self
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        self.webView = webView
        webView.navigationDelegate = self
        scheduleTimeout()
        webView.load(URLRequest(url: loginURL))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didEvaluate else { return }
        pendingEvaluation?.cancel()
        AppLog.network.debug("[\(self.id)] browser navigation finished at \(webView.url?.absoluteString ?? "<nil>"), waiting for idle")
        let item = DispatchWorkItem { [weak self, weak webView] in
            guard let self, let webView else { return }
            guard !self.didEvaluate else { return }
            self.didEvaluate = true
            self.evaluateFetch(in: webView)
        }
        pendingEvaluation = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure("nav: \(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure("nav: \(error.localizedDescription)"))
    }

    private func evaluateFetch(in webView: WKWebView) {
        webView.evaluateJavaScript(fetchScript()) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.finish(.failure("js: \(error.localizedDescription)"))
                return
            }
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.finish(.failure("fetch result parse"))
                return
            }
            if let error = obj["error"] as? String {
                self.finish(.failure(error))
                return
            }
            let status = obj["status"] as? Int ?? 0
            let body = obj["body"] as? String ?? ""
            let page = BrowserPageContext(
                url: obj["finalURL"] as? String ?? webView.url?.absoluteString ?? "",
                title: obj["title"] as? String ?? "",
                text: obj["pageText"] as? String ?? ""
            )
            self.finish(.success(status: status, data: Data(body.utf8), page: page))
        }
    }

    private func fetchScript() -> String {
        let headersJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: headers, options: []),
           let json = String(data: data, encoding: .utf8) {
            headersJSON = json
        } else {
            headersJSON = "{}"
        }
        return """
        (function() {
          try {
            const xhr = new XMLHttpRequest();
            xhr.open(\(jsString(method)), \(jsString(targetURL.absoluteString)), false);
            xhr.withCredentials = true;
            const headers = \(headersJSON);
            for (const key of Object.keys(headers)) {
              xhr.setRequestHeader(key, headers[key]);
            }
            xhr.send(null);
            return JSON.stringify({
              status: xhr.status,
              body: xhr.responseText || "",
              finalURL: document.location.href,
              title: document.title || "",
              pageText: document.body ? document.body.innerText.replace(/\\s+/g, " ").slice(0, 1000) : ""
            });
          } catch (error) {
            return JSON.stringify({ error: String(error && error.message ? error.message : error) });
          }
        })()
        """
    }

    private func jsString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "\"\""
    }

    private func scheduleTimeout() {
        let item = DispatchWorkItem { [weak self] in
            self?.finish(.failure("timeout"))
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)
    }

    private func finish(_ result: BrowserFetchResult) {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        timeout?.cancel()
        timeout = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        completion(result)
        retainedSelf = nil
    }
}
