import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

public struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    let onRefresh: () -> Void
    @State private var refreshing = false
    @State private var showingSettings = false
    @State private var draggedProviderId: String?
    @AppStorage("tb.providerOrderIds") private var providerOrderIdsJSON: String = ""

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
                mainView
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
                VStack(alignment: .leading, spacing: 8) {
                    let providers = ProvidersRegistry.default.enabled()
                    if providers.isEmpty {
                        ContentUnavailableView(
                            "没有启用的 Provider",
                            systemImage: "slider.horizontal.3",
                            description: Text("打开设置选择要显示的服务")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(providers, id: \.id) { p in
                            ProviderSectionView(
                                provider: p,
                                snapshot: appState.snapshots[p.id],
                                onLogin: { Task { await loginFlow(for: p) } },
                                onRefresh: { onRefresh() }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .opacity(draggedProviderId == p.id ? 0.45 : 1)
                            .scaleEffect(draggedProviderId == p.id ? 0.985 : 1)
                            .animation(.easeInOut(duration: 0.16), value: draggedProviderId)
                            .onDrag {
                                beginProviderDrag(p.id)
                                return NSItemProvider(object: p.id as NSString)
                            } preview: {
                                ProviderDragPreview(provider: p)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ProviderReorderDropDelegate(
                                    targetProviderId: p.id,
                                    draggedProviderId: $draggedProviderId,
                                    providerOrderIdsJSON: $providerOrderIdsJSON
                                )
                            )
                        }
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.18), value: ProvidersRegistry.default.enabled().map(\.id))
                .onDrop(
                    of: [.text],
                    delegate: ProviderDragResetDropDelegate(draggedProviderId: $draggedProviderId)
                )
            }

            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless)
                Text("v0.1").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    @MainActor
    private func loginFlow(for p: any ProviderAdapter) async {
        let mgr = WebViewSessionManager()
        await mgr.startLogin(for: p)
        onRefresh()
    }

    private func beginProviderDrag(_ providerId: String) {
        draggedProviderId = providerId
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if draggedProviderId == providerId {
                draggedProviderId = nil
            }
        }
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
    @Binding var providerOrderIdsJSON: String

    func dropEntered(info: DropInfo) {
        guard let draggedProviderId, draggedProviderId != targetProviderId else { return }
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
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private func currentOrderIds() -> [String] {
        let defaultIds = ProvidersRegistry.default.adapters.map(\.id)
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

    func performDrop(info: DropInfo) -> Bool {
        draggedProviderId = nil
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

                Section("Provider") {
                    ForEach(ProvidersRegistry.default.ordered(), id: \.id) { provider in
                        Toggle(isOn: providerBinding(provider)) {
                            Label(provider.displayName, systemImage: provider.iconSystemName)
                        }
                        .toggleStyle(.switch)
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
                    setEnabledProviderIds(Set(ProvidersRegistry.default.adapters.map(\.id)))
                    onRefresh()
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(height: 480)
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
        for provider in ProvidersRegistry.default.adapters where !enabled.contains(provider.id) {
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
