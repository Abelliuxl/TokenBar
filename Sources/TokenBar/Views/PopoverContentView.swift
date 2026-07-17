import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

public struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    let onRefresh: () -> Void
    @State private var refreshing = false
    @State private var showingSettings = false
    @State private var draggedProviderId: String?
    @State private var dropTargetProviderId: String?
    @AppStorage("tb.providerOrderIds") private var providerOrderIdsJSON: String = ""
    @AppStorage("tb.balanceCardsPerRow") private var balanceCardsPerRow: Bool = true
    @AppStorage(CustomProviderStore.storageKey) private var customProvidersJSON: String = ""

    public init(appState: AppState, onRefresh: @escaping () -> Void) {
        self.appState = appState
        self.onRefresh = onRefresh
    }

    public var body: some View {
        Group {
            if showingSettings {
                SettingsPanelView(
                    appState: appState,
                    onBack: { showingSettings = false },
                    onRefresh: onRefresh
                )
            } else {
                mainView.id(customProvidersJSON)
            }
        }
        .frame(width: 340)
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TokenBar").font(.headline)
                Spacer()
                Button(action: {
                    refreshing = true
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { refreshing = false }
                }) {
                    Image(systemName: refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }.buttonStyle(.borderless)
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                let providers = ProvidersRegistry.default.enabled()
                if providers.isEmpty {
                    ContentUnavailableView(
                        "没有启用的 Provider",
                        systemImage: "slider.horizontal.3",
                        description: Text("打开设置选择要显示的服务")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding()
                } else {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(providerRows(from: providers)) { row in
                            if row.isBalanceRow {
                                GridRow {
                                    providerTile(row.primary, compactBalance: true)
                                    if let secondary = row.secondary {
                                        providerTile(secondary, compactBalance: true)
                                    } else {
                                        Color.clear
                                    }
                                }
                            } else {
                                GridRow {
                                    providerTile(row.primary, compactBalance: false)
                                        .gridCellColumns(2)
                                }
                            }
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.18), value: providers.map(\.id))
                    .onDrop(
                        of: [.text],
                        delegate: ProviderDragResetDropDelegate(
                            draggedProviderId: $draggedProviderId,
                            dropTargetProviderId: $dropTargetProviderId
                        )
                    )
                }
            }

            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless)
                Text(AppVersion.display).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    @MainActor
    private func loginFlow(for p: any ProviderAdapter) async {
        let mgr = WebViewSessionManager()
        if let existingCustom = CustomProviderStore.definitions().first(where: { $0.id == p.id }) {
            await mgr.startLogin(for: p) { rule in
                CustomProviderStore.upsert(CustomProviderDefinition(
                    id: existingCustom.id,
                    displayName: existingCustom.displayName,
                    loginURL: existingCustom.loginURL,
                    iconSystemName: existingCustom.iconSystemName,
                    rule: rule
                ))
            }
        } else {
            // Built-in providers only need a clean persistent WebView login.
            // Do not inject the custom-site network probe into third-party
            // authentication pages; it replaces fetch/XHR and can disrupt them.
            await mgr.startLogin(for: p)
        }
        onRefresh()
    }

    private func beginProviderDrag(_ providerId: String) {
        draggedProviderId = providerId
        dropTargetProviderId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if draggedProviderId == providerId {
                draggedProviderId = nil
                dropTargetProviderId = nil
            }
        }
    }

    private func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func providerTile(_ provider: any ProviderAdapter, compactBalance: Bool) -> some View {
        ProviderSectionView(
            provider: provider,
            snapshot: appState.snapshots[provider.id],
            onLogin: { Task { await loginFlow(for: provider) } },
            onRefresh: { onRefresh() },
            onOpenWebPage: { openInBrowser(provider.loginURL) },
            compactBalance: compactBalance
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: compactBalance ? 9 : 6, style: .continuous))
        .opacity(draggedProviderId == provider.id ? 0.45 : 1)
        .scaleEffect(draggedProviderId == provider.id ? 0.985 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: compactBalance ? 9 : 6, style: .continuous)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .opacity(dropTargetProviderId == provider.id && draggedProviderId != provider.id ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.16), value: draggedProviderId)
        .animation(.easeInOut(duration: 0.16), value: dropTargetProviderId)
        .onDrag {
            beginProviderDrag(provider.id)
            return NSItemProvider(object: provider.id as NSString)
        } preview: {
            ProviderDragPreview(provider: provider)
        }
        .onDrop(
            of: [.text],
            delegate: ProviderReorderDropDelegate(
                targetProviderId: provider.id,
                draggedProviderId: $draggedProviderId,
                dropTargetProviderId: $dropTargetProviderId,
                providerOrderIdsJSON: $providerOrderIdsJSON
            )
        )
    }

    private func providerRows(from providers: [any ProviderAdapter]) -> [ProviderLayoutRow] {
        var rows: [ProviderLayoutRow] = []
        var pendingBalance: (any ProviderAdapter)?

        for provider in providers {
            if balanceCardsPerRow && isBalanceProvider(provider) {
                if let pending = pendingBalance {
                    rows.append(ProviderLayoutRow(primary: pending, secondary: provider, isBalanceRow: true))
                    pendingBalance = nil
                } else {
                    pendingBalance = provider
                }
            } else {
                if let pending = pendingBalance {
                    rows.append(ProviderLayoutRow(primary: pending, secondary: nil, isBalanceRow: true))
                    pendingBalance = nil
                }
                rows.append(ProviderLayoutRow(primary: provider, secondary: nil, isBalanceRow: false))
            }
        }
        if let pendingBalance {
            rows.append(ProviderLayoutRow(primary: pendingBalance, secondary: nil, isBalanceRow: true))
        }
        return rows
    }

    private func isBalanceProvider(_ provider: any ProviderAdapter) -> Bool {
        guard let snapshot = appState.snapshots[provider.id],
              case .ok = snapshot.status,
              !snapshot.quotas.isEmpty else {
            return false
        }
        return snapshot.quotas.allSatisfy(\.isCurrency)
    }
}

private struct ProviderLayoutRow: Identifiable {
    let primary: any ProviderAdapter
    let secondary: (any ProviderAdapter)?
    let isBalanceRow: Bool

    var id: String {
        [primary.id, secondary?.id ?? "empty", isBalanceRow ? "balance" : "full"].joined(separator: "-")
    }
}

private struct ProviderDragPreview: View {
    let provider: any ProviderAdapter

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconSystemName)
            Text(provider.displayName)
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 6)
    }
}

private struct ProviderReorderDropDelegate: DropDelegate {
    let targetProviderId: String
    @Binding var draggedProviderId: String?
    @Binding var dropTargetProviderId: String?
    @Binding var providerOrderIdsJSON: String

    func dropEntered(info: DropInfo) {
        guard let draggedProviderId, draggedProviderId != targetProviderId else { return }
        dropTargetProviderId = targetProviderId
        var ids = currentOrderIds()
        guard let from = ids.firstIndex(of: draggedProviderId),
              let to = ids.firstIndex(of: targetProviderId) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            save(ids)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedProviderId = nil
        dropTargetProviderId = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if dropTargetProviderId == targetProviderId {
            dropTargetProviderId = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private func currentOrderIds() -> [String] {
        let defaultIds = ProvidersRegistry.default.all().map(\.id)
        guard let data = providerOrderIdsJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String].self, from: data),
              !stored.isEmpty else {
            return defaultIds
        }
        var seen = Set<String>()
        var result = stored.filter { id in
            guard defaultIds.contains(id), !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
        result.append(contentsOf: defaultIds.filter { !seen.contains($0) })
        return result
    }

    private func save(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        providerOrderIdsJSON = json
    }
}

private struct ProviderDragResetDropDelegate: DropDelegate {
    @Binding var draggedProviderId: String?
    @Binding var dropTargetProviderId: String?

    func performDrop(info: DropInfo) -> Bool {
        draggedProviderId = nil
        dropTargetProviderId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SettingsPanelView: View {
    @ObservedObject var appState: AppState
    let onBack: () -> Void
    let onRefresh: () -> Void
    @AppStorage("tb.launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("tb.enabledProviderIds") private var enabledProviderIdsJSON: String = ""
    @AppStorage("tb.providerOrderIds") private var providerOrderIdsJSON: String = ""
    @AppStorage("tb.balanceCardsPerRow") private var balanceCardsPerRow: Bool = true
    @AppStorage(CustomProviderStore.storageKey) private var customProvidersJSON: String = ""
    @AppStorage(DiagnosticLog.enabledKey) private var diagnosticLoggingEnabled: Bool = false
    @State private var showingAddCustomProvider = false
    @State private var customProviderName = ""
    @State private var customProviderURL = ""
    @State private var configuringCustomProvider = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("设置").font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section {
                    Toggle("开机启动", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, newValue in
                            Self.setLaunchAtLogin(newValue)
                        }
                }

                Section("显示") {
                    Toggle("余额每行显示两个", isOn: $balanceCardsPerRow)
                        .toggleStyle(.switch)
                    Text(balanceCardsPerRow ? "两列卡片会隐藏图标，优先显示完整名称和余额。" : "余额将与进度额度一样，每项独占一行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("诊断") {
                    Toggle("保存诊断日志", isOn: $diagnosticLoggingEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: diagnosticLoggingEnabled) { _, enabled in
                            if enabled { DiagnosticLog.enabled() }
                        }
                    Text("默认关闭。开启后会记录抓取阶段和错误原因，但不会保存 Cookie、页面正文或接口响应内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if diagnosticLoggingEnabled {
                        HStack {
                            Button("打开日志文件夹") {
                                try? FileManager.default.createDirectory(at: DiagnosticLog.directoryURL, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(DiagnosticLog.directoryURL)
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            Button("清空日志") { DiagnosticLog.clear() }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Provider") {
                    ForEach(ProvidersRegistry.default.ordered(), id: \.id) { provider in
                        Toggle(isOn: providerBinding(provider)) {
                            Label(provider.displayName, systemImage: provider.iconSystemName)
                        }
                        .toggleStyle(.switch)
                    }
                }

                Section("自定义站点") {
                    if CustomProviderStore.definitions().isEmpty {
                        Text("还没有自定义站点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(CustomProviderStore.definitions()) { definition in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.displayName)
                                    Text(definition.rule.source == .dom ? "页面字段" : "接口字段")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    deleteCustomProvider(definition)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除自定义站点")
                            }
                        }
                    }

                    if showingAddCustomProvider {
                        TextField("站点名称", text: $customProviderName)
                        HStack(spacing: 6) {
                            TextField("登录网址", text: $customProviderURL)
                            Button {
                                pasteCustomProviderURL()
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .opacity(0.65)
                            .help("从剪贴板粘贴 URL")
                        }
                        HStack {
                            Button(configuringCustomProvider ? "等待字段选择…" : "打开并选择字段") {
                                startCustomProviderSetup()
                            }
                            .disabled(configuringCustomProvider || customProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isHTTPURL(customProviderURL))
                            Button("取消") {
                                showingAddCustomProvider = false
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button {
                            customProviderName = ""
                            customProviderURL = "https://"
                            showingAddCustomProvider = true
                        } label: {
                            Label("添加自定义站点", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("全部关闭") {
                    setEnabledProviderIds([])
                    clearDisabledSnapshots()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("全部开启") {
                    setEnabledProviderIds(Set(ProvidersRegistry.default.all().map(\.id)))
                    onRefresh()
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(height: 600)
    }

    private func startCustomProviderSetup() {
        let name = customProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlText = customProviderURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText), isHTTPURL(urlText) else { return }

        configuringCustomProvider = true
        Task { @MainActor in
            let manager = WebViewSessionManager()
            if let rule = await manager.startCustomProviderSetup(displayName: name, loginURL: url) {
                let definition = CustomProviderDefinition(
                    displayName: name,
                    loginURL: url.absoluteString,
                    rule: rule
                )
                CustomProviderStore.upsert(definition)
                var enabled = enabledProviderIds
                enabled.insert(definition.id)
                setEnabledProviderIds(enabled)
                onRefresh()
                customProviderName = ""
                customProviderURL = ""
                showingAddCustomProvider = false
            }
            configuringCustomProvider = false
        }
    }

    private func deleteCustomProvider(_ definition: CustomProviderDefinition) {
        CustomProviderStore.remove(id: definition.id)
        var enabled = enabledProviderIds
        enabled.remove(definition.id)
        setEnabledProviderIds(enabled)
        let order: [String]
        if let data = providerOrderIdsJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String].self, from: data) {
            order = stored.filter { $0 != definition.id }
        } else {
            order = []
        }
        if let data = try? JSONEncoder().encode(order), let json = String(data: data, encoding: .utf8) {
            providerOrderIdsJSON = json
        }
        appState.clear(providerId: definition.id)
        onRefresh()
    }

    private func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private func pasteCustomProviderURL() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        customProviderURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerBinding(_ provider: any ProviderAdapter) -> Binding<Bool> {
        Binding(
            get: { enabledProviderIds.contains(provider.id) },
            set: { enabled in
                var next = enabledProviderIds
                if enabled {
                    next.insert(provider.id)
                } else {
                    next.remove(provider.id)
                    appState.clear(providerId: provider.id)
                }
                setEnabledProviderIds(next)
                if enabled { onRefresh() }
            }
        )
    }

    private var enabledProviderIds: Set<String> {
        guard let data = enabledProviderIdsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(values)
    }

    private func setEnabledProviderIds(_ ids: Set<String>) {
        let values = ids.sorted()
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        enabledProviderIdsJSON = json
    }

    private func clearDisabledSnapshots() {
        let enabled = enabledProviderIds
        for provider in ProvidersRegistry.default.all() where !enabled.contains(provider.id) {
            appState.clear(providerId: provider.id)
        }
    }

    /// Register/unregister the app as a Login Item via SMAppService (macOS 13+).
    /// The build target is macOS 14, so this API is always available.
    private static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.lifecycle.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }
}
