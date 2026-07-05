import Foundation

/// Minimal Chrome DevTools Protocol client over WebSocket.
///
/// Uses a URLSessionWebSocketDelegate to detect when the WebSocket opens
/// (`didOpenWithProtocol`), at which point the receive loop is started and
/// CDP domain-enable commands are sent.
public final class CDPClient {
    // MARK: - Errors
    public enum Error: Swift.Error, LocalizedError {
        case chromeNotReachable(port: Int)
        case noPageFound
        case wsNotConnected
        case commandFailed(method: String, message: String)
        case unexpectedResponse
        case timeout(seconds: TimeInterval)

        public var errorDescription: String? {
            switch self {
            case .chromeNotReachable(let port):
                return "Chrome not reachable on port \(port).\nStart Chrome with:\n  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=\(port)"
            case .noPageFound:
                return "No suitable page tab found in Chrome"
            case .wsNotConnected:
                return "WebSocket not connected"
            case .commandFailed(let method, let message):
                return "CDP command '\(method)' failed: \(message)"
            case .unexpectedResponse:
                return "Unexpected CDP response format"
            case .timeout(let s):
                return "CDP command timed out after \(s)s"
            }
        }
    }

    // MARK: - Setup

    /// Create a fresh page tab and open the WebSocket.
    public func connectAsync(host: String = "localhost", port: Int = 9222,
                             navigateTo: String? = nil) async throws {
        // 1. Verify Chrome is reachable and list page targets
        let listURL = URL(string: "http://\(host):\(port)/json")!
        let (data, resp) = try await URLSession.shared.data(from: listURL)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw Error.chromeNotReachable(port: port)
        }
        guard let pages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Error.unexpectedResponse
        }

        // 2. Find an existing page tab (any page type)
        guard let target = pages.first(where: { ($0["type"] as? String) == "page" }),
              let wsURL = target["webSocketDebuggerUrl"] as? String,
              let url = URL(string: wsURL) else {
            throw Error.noPageFound
        }

        // 3. Open WebSocket with a dedicated delegate object
        let delegate = _Delegate(client: self)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        self.ownedSession = session
        self.webSocketDelegate = delegate
        let task = session.webSocketTask(with: url)
        self.webSocket = task
        task.resume()

        // 4. Wait a moment for the WebSocket to open
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    /// Send a CDP command and await the result.
    @discardableResult
    public func send(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any]? {
        let id = nextId; nextId += 1
        var dict: [String: Any] = ["id": id, "method": method]
        if let params = params { dict["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])

        guard let ws = webSocket else { throw Error.wsNotConnected }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any]?, Swift.Error>) in
            stateQueue.sync { pending[id] = cont }
            guard let str = String(data: data, encoding: .utf8) else {
                cont.resume(throwing: Error.unexpectedResponse)
                return
            }
            ws.send(.string(str)) { error in
                if let error = error {
                    let c = self.stateQueue.sync { self.pending.removeValue(forKey: id) }
                    c?.resume(throwing: error)
                }
            }
        }
    }

    /// Async sequence of CDP events.
    public var events: AsyncStream<CDPEvent> {
        AsyncStream { continuation in
            stateQueue.sync {
                for event in eventBuffer { continuation.yield(event) }
                eventBuffer.removeAll()
                eventCont = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.stateQueue.sync { self?.eventCont = nil }
            }
        }
    }

    /// Close the WebSocket and clean up.
    public func disconnect() {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        ownedSession?.invalidateAndCancel()
        ownedSession = nil
        webSocketDelegate = nil
        stateQueue.sync {
            for (_, c) in pending { c.resume(throwing: Error.wsNotConnected) }
            pending.removeAll()
            eventCont?.finish()
            eventCont = nil
        }
        isDisconnecting = false
    }

    deinit { disconnect() }

    // MARK: - Private

    private var webSocket: URLSessionWebSocketTask?
    private var ownedSession: URLSession?
    private var webSocketDelegate: _Delegate?
    private var nextId = 1
    private var isDisconnecting = false

    private let stateQueue = DispatchQueue(label: "cdp.lock")
    private var pending: [Int: CheckedContinuation<[String: Any]?, Swift.Error>] = [:]
    private var eventCont: AsyncStream<CDPEvent>.Continuation?
    private var eventBuffer: [CDPEvent] = []

    /// Called by _Delegate when the WebSocket opens.
    fileprivate func onWebSocketOpen(task: URLSessionWebSocketTask) {
        // Start receive loop and fire domain enable commands
        startReceiveLoop(on: task)
        fireAndForget(task, "Network.enable")
        fireAndForget(task, "Page.enable")
        fireAndForget(task, "Runtime.enable")
    }

    private func startReceiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                self.handleMessage(msg)
                self.startReceiveLoop(on: task)
            case .failure:
                self.disconnect()
            }
        }
    }

    private func fireAndForget(_ task: URLSessionWebSocketTask, _ method: String, params: [String: Any]? = nil) {
        let id = nextId; nextId += 1
        var dict: [String: Any] = ["id": id, "method": method]
        if let params = params { dict["params"] = params }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task.send(.string(str), completionHandler: { _ in })
    }

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) {
        let str: String
        switch msg {
        case .string(let s): str = s
        case .data(let d): str = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let id = json["id"] as? Int {
            let c = stateQueue.sync { pending.removeValue(forKey: id) }
            if let c = c {
                if let error = json["error"] as? [String: Any] {
                    let msg = error["message"] as? String ?? "unknown"
                    c.resume(throwing: Error.commandFailed(method: "id=\(id)", message: msg))
                } else {
                    c.resume(returning: json["result"] as? [String: Any])
                }
            }
            return
        }

        guard let method = json["method"] as? String else { return }
        let params = json["params"] as? [String: Any] ?? [:]
        let event = CDPEvent(method: method, params: params)
        stateQueue.sync {
            if let cont = eventCont { cont.yield(event) }
            else { eventBuffer.append(event) }
        }
    }
}

// MARK: - Private delegate (separate object — avoids a CDP WebSocket bug on Chrome 149)

extension CDPClient {
    fileprivate class _Delegate: NSObject, URLSessionWebSocketDelegate {
        weak var client: CDPClient?
        init(client: CDPClient) { self.client = client }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didOpenWithProtocol protocol: String?) {
            client?.onWebSocketOpen(task: webSocketTask)
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                        reason: Data?) {
            client?.disconnect()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Swift.Error?) {
            if error != nil { client?.disconnect() }
        }
    }
}

// MARK: - CDP Event

public struct CDPEvent: @unchecked Sendable {
    public let method: String
    public let params: [String: Any]
    public subscript(key: String) -> Any? { params[key] }
}
