import SwiftUI

public struct ProviderSectionView: View {
    let provider: any ProviderAdapter
    let snapshot: Snapshot?
    let onLogin: () -> Void
    let onRefresh: () -> Void

    public init(provider: any ProviderAdapter, snapshot: Snapshot?, onLogin: @escaping () -> Void, onRefresh: @escaping () -> Void) {
        self.provider = provider
        self.snapshot = snapshot
        self.onLogin = onLogin
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: provider.iconSystemName)
                Text(provider.displayName).bold()
                Spacer()
                if snapshot == nil {
                    Button("登录", action: onLogin).buttonStyle(.borderless)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.borderless)
                }
            }
            if let snap = snapshot {
                switch snap.status {
                case .needsRelogin:
                    Label("Session 过期", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Button("重新登录", action: onLogin).buttonStyle(.bordered)
                case .error(let msg):
                    Text(msg).font(.caption).foregroundStyle(.red)
                case .ok:
                    ForEach(snap.quotas) { q in QuotaRowView(quota: q) }
                    if snap.quotas.isEmpty {
                        Text("无数据").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("加载中…").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
        }
    }
}
