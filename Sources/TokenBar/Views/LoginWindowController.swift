import AppKit
import WebKit

@MainActor
public final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var onFinish: (() -> Void)?
    private var onFieldRuleSelected: ((CustomFieldRule) -> Void)?
    private var networkResponses: [CapturedNetworkResponse] = []
    private var selectionMode = false
    private let selectFieldButton = NSButton(title: "选择字段", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    public init(provider: any ProviderAdapter,
                onFinish: @escaping () -> Void,
                onFieldRuleSelected: ((CustomFieldRule) -> Void)? = nil) {
        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "登录 \(provider.displayName)"
        win.center()
        super.init(window: win)
        self.onFinish = onFinish
        self.onFieldRuleSelected = onFieldRuleSelected

        AppLog.auth.notice("Login window opened for \(provider.displayName)")

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        win.contentView = content

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 10
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        selectFieldButton.target = self
        selectFieldButton.action = #selector(toggleFieldSelection)
        selectFieldButton.bezelStyle = .rounded
        selectFieldButton.isHidden = onFieldRuleSelected == nil
        toolbar.addArrangedSubview(selectFieldButton)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        toolbar.addArrangedSubview(statusLabel)

        content.addSubview(toolbar)

        let config = WKWebViewConfiguration()
        // Use the default (persistent) website data store so cookies set during
        // login survive across app restarts and can be reused by polling.
        config.websiteDataStore = .default()
        if onFieldRuleSelected != nil {
            config.userContentController.add(self, name: "tokenBarFieldProbe")
            config.userContentController.add(self, name: "tokenBarFieldSelection")
            config.userContentController.addUserScript(WKUserScript(
                source: FieldProbeScripts.networkCapture,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView.navigationDelegate = self
        content.addSubview(self.webView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

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
        window?.orderFrontRegardless()
    }

    @objc private func toggleFieldSelection() {
        guard onFieldRuleSelected != nil else { return }
        selectionMode.toggle()
        if selectionMode {
            selectFieldButton.title = "停止选择"
            statusLabel.stringValue = "正在准备字段选择，页面将刷新一次以捕获接口数据…"
            webView.configuration.userContentController.addUserScript(WKUserScript(
                source: FieldProbeScripts.enableCaptureAtDocumentStart,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            webView.evaluateJavaScript(FieldProbeScripts.startSelection) { [weak self] _, _ in
                guard let self else { return }
                self.webView.reload()
            }
        } else {
            stopFieldSelection()
        }
    }

    private func stopFieldSelection() {
        selectionMode = false
        selectFieldButton.title = "选择字段"
        statusLabel.stringValue = ""
        webView.evaluateJavaScript(FieldProbeScripts.stopSelection, completionHandler: nil)
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: FieldProbeScripts.networkCapture,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard selectionMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak webView] in
            guard let self, let webView, self.selectionMode else { return }
            webView.evaluateJavaScript(FieldProbeScripts.startSelection, completionHandler: nil)
            self.statusLabel.stringValue = "请选择页面中的余额、额度或用量文本"
        }
    }

    public nonisolated func userContentController(_ userContentController: WKUserContentController,
                                                  didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            self?.handleScriptMessage(message)
        }
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard selectionMode else { return }
        if let payload = message.body as? [String: Any],
           payload["type"] as? String == "network" {
            captureNetworkResponse(payload)
            return
        }
        guard let json = message.body as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(FieldSelectionPayload.self, from: data) else {
            return
        }
        let networkCandidates = makeNetworkCandidates(selectedText: payload.text)
        let candidates = uniqueCandidates((payload.candidates + networkCandidates).sorted { $0.score > $1.score })
        presentCandidatePicker(candidates, selectedText: payload.text)
    }

    private func captureNetworkResponse(_ payload: [String: Any]) {
        guard let url = payload["url"] as? String,
              let body = payload["body"] as? String,
              !body.isEmpty else { return }
        let response = CapturedNetworkResponse(
            url: url,
            method: payload["method"] as? String ?? "GET",
            body: body,
            requestBody: payload["requestBody"] as? String
        )
        networkResponses.append(response)
        if networkResponses.count > 80 {
            networkResponses.removeFirst(networkResponses.count - 80)
        }
    }

    private func presentCandidatePicker(_ candidates: [FieldCandidate], selectedText: String) {
        guard !candidates.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "没有找到可保存的字段"
            alert.informativeText = "请重新选择包含余额、额度或数字的文本；如果网站通过接口加载数据，请先刷新页面。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "选择要保存的字段"
        alert.informativeText = "已选文本：\(selectedText)\n候选项按可能性从高到低排列。"
        let popup = NSPopUpButton(frame: .init(x: 0, y: 0, width: 560, height: 26), pullsDown: false)
        candidates.forEach { popup.addItem(withTitle: $0.title) }
        alert.accessoryView = popup
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn,
           candidates.indices.contains(popup.indexOfSelectedItem) {
            onFieldRuleSelected?(candidates[popup.indexOfSelectedItem].rule())
            stopFieldSelection()
        }
    }

    private func uniqueCandidates(_ candidates: [FieldCandidate]) -> [FieldCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !seen.contains(candidate.id) else { return false }
            seen.insert(candidate.id)
            return true
        }
    }

    private func makeNetworkCandidates(selectedText: String) -> [FieldCandidate] {
        let selectedNumbers = CustomProviderRuntime.numbers(in: selectedText)
        let valueKind = selectedText.contains("%") ? "percent" : "balance"
        let unit = selectedText.first(where: { "¥￥$€%".contains($0) }).map(String.init) ?? ""
        var result: [FieldCandidate] = []

        for response in networkResponses.reversed() {
            guard let data = response.body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectNetworkValues(
                root,
                path: "",
                keyHint: "",
                response: response,
                selectedNumbers: selectedNumbers,
                valueKind: valueKind,
                unit: unit,
                result: &result
            )
        }
        return result.sorted { $0.score > $1.score }
    }

    private func collectNetworkValues(_ value: Any,
                                      path: String,
                                      keyHint: String,
                                      response: CapturedNetworkResponse,
                                      selectedNumbers: [Double],
                                      valueKind: String,
                                      unit: String,
                                      result: inout [FieldCandidate]) {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                collectNetworkValues(child, path: childPath, keyHint: key, response: response,
                                     selectedNumbers: selectedNumbers, valueKind: valueKind, unit: unit, result: &result)
            }
            return
        }
        if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                let childPath = path.isEmpty ? String(index) : "\(path).\(index)"
                collectNetworkValues(child, path: childPath, keyHint: keyHint, response: response,
                                     selectedNumbers: selectedNumbers, valueKind: valueKind, unit: unit, result: &result)
            }
            return
        }

        let text: String
        if let number = value as? NSNumber { text = number.stringValue }
        else if let string = value as? String { text = string }
        else { return }
        guard let number = CustomProviderRuntime.numbers(in: text).first else { return }

        let semantic = keyHint.range(of: "balance|quota|credit|remaining|available|wallet|usage|limit|token|余额|额度|剩余|可用|用量|积分|次数", options: .regularExpression) != nil
        let matchesSelected = selectedNumbers.contains { abs($0 - number) < 0.000001 }
        guard semantic || matchesSelected else { return }

        var score = 48.0
        if semantic { score += 42 }
        if matchesSelected { score += 34 }
        if response.url.lowercased().contains("balance") || response.url.lowercased().contains("quota") { score += 12 }
        result.append(FieldCandidate(
            source: .api,
            label: keyHint.isEmpty ? "接口字段" : keyHint,
            preview: text,
            score: score,
            selector: nil,
            endpoint: response.url,
            method: response.method,
            body: response.requestBody,
            jsonPath: path,
            valueKind: valueKind,
            unit: unit
        ))
    }

    @objc private func windowWillClose() {
        AppLog.auth.notice("Login window closed")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tokenBarFieldProbe")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "tokenBarFieldSelection")
        onFinish?()
        onFinish = nil
        onFieldRuleSelected = nil
    }
}

private struct CapturedNetworkResponse {
    let url: String
    let method: String
    let body: String
    let requestBody: String?
}

private struct FieldSelectionPayload: Decodable {
    let type: String
    let text: String
    let candidates: [FieldCandidate]
}
