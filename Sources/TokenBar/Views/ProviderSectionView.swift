import SwiftUI

public struct ProviderSectionView: View {
    let provider: any ProviderAdapter
    let snapshot: Snapshot?
    let onLogin: () -> Void
    let onRefresh: () -> Void
    let onOpenWebPage: () -> Void
    let compactBalance: Bool
    @State private var credentialMode: ProviderFetchMode?
    @State private var selectedModeId: String

    public init(provider: any ProviderAdapter,
                snapshot: Snapshot?,
                onLogin: @escaping () -> Void,
                onRefresh: @escaping () -> Void,
                onOpenWebPage: @escaping () -> Void,
                compactBalance: Bool = false) {
        self.provider = provider
        self.snapshot = snapshot
        self.onLogin = onLogin
        self.onRefresh = onRefresh
        self.onOpenWebPage = onOpenWebPage
        self.compactBalance = compactBalance
        if let multiMode = provider as? any MultiModeProviderAdapter {
            _selectedModeId = State(initialValue: ProviderFetchModeStore.selectedModeId(for: multiMode))
        } else {
            _selectedModeId = State(initialValue: "")
        }
    }

    public var body: some View {
        Group {
            if compactBalance {
                balanceCard
            } else {
                fullSection
            }
        }
        .contextMenu {
            Button("打开网页", systemImage: "safari") {
                onOpenWebPage()
            }
            if let multiMode = provider as? any MultiModeProviderAdapter {
                Menu("爬取模式", systemImage: "arrow.triangle.branch") {
                    ForEach(multiMode.fetchModes) { mode in
                        Button {
                            choose(mode: mode, provider: multiMode)
                        } label: {
                            if selectedModeId == mode.id {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $credentialMode) { mode in
            ProviderCredentialsView(providerId: provider.id, mode: mode) {
                ProviderFetchModeStore.setSelectedModeId(mode.id, providerId: provider.id)
                selectedModeId = mode.id
                credentialMode = nil
                onRefresh()
            } onCancel: {
                credentialMode = nil
            }
        }
    }

    private func choose(mode: ProviderFetchMode, provider: any MultiModeProviderAdapter) {
        // Selecting the already-active credential mode doubles as "edit credentials".
        if selectedModeId == mode.id && !mode.credentialFields.isEmpty {
            credentialMode = mode
            return
        }
        if mode.credentialFields.isEmpty || ProviderCredentialStore.hasCredentials(providerId: provider.id, mode: mode) {
            ProviderFetchModeStore.setSelectedModeId(mode.id, providerId: provider.id)
            selectedModeId = mode.id
            onRefresh()
        } else {
            credentialMode = mode
        }
    }

    private var fullSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            providerHeader
            if let snap = snapshot {
                switch snap.status {
                case .needsRelogin:
                    Label("需要登录或登录态无效", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Button("重新登录", action: onLogin)
                        .buttonStyle(.bordered)
                case .error(let msg):
                    Text(msg).font(.caption).foregroundStyle(.red)
                        .lineLimit(4)
                    Button("打开页面", action: onLogin)
                        .buttonStyle(.bordered)
                case .ok:
                    ForEach(snap.quotas) { q in QuotaRowView(quota: q) }
                    if snap.quotas.isEmpty {
                        Text("没有抓到用量数据").font(.caption).foregroundStyle(.secondary)
                        Button("打开页面", action: onLogin)
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("未登录或等待刷新").font(.caption).foregroundStyle(.secondary)
                Button("登录", action: onLogin)
                    .buttonStyle(.bordered)
            }
            Divider()
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            providerHeader
            if let snapshot {
                ForEach(snapshot.quotas) { quota in
                    QuotaRowView(quota: quota)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var providerHeader: some View {
        HStack(spacing: 7) {
            if !compactBalance {
                Image(systemName: provider.iconSystemName)
            }
            Text(provider.displayName).bold()
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct ProviderCredentialsView: View {
    let providerId: String
    let mode: ProviderFetchMode
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var values: [String: String] = [:]
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置\(mode.title)").font(.headline)
            Text("凭据只保存在这台 Mac 的钥匙串中。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(mode.credentialFields) { field in
                VStack(alignment: .leading, spacing: 5) {
                    Text(field.title).font(.caption)
                    if field.isSecret {
                        SecureField(field.placeholder, text: binding(for: field.id))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(field.placeholder, text: binding(for: field.id))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            if saveFailed {
                Text("写入 macOS 钥匙串失败。").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("保存并切换") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(mode.credentialFields.contains { (values[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            for field in mode.credentialFields {
                values[field.id] = ProviderCredentialStore.value(providerId: providerId, modeId: mode.id, fieldId: field.id) ?? ""
            }
        }
    }

    private func binding(for fieldId: String) -> Binding<String> {
        Binding(get: { values[fieldId] ?? "" }, set: { values[fieldId] = $0 })
    }

    private func save() {
        let saved = mode.credentialFields.allSatisfy { field in
            ProviderCredentialStore.setValue(
                (values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                providerId: providerId,
                modeId: mode.id,
                fieldId: field.id
            )
        }
        if saved { onSave() } else { saveFailed = true }
    }
}
