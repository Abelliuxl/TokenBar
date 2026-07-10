import SwiftUI

public struct ProviderSectionView: View {
    let provider: any ProviderAdapter
    let snapshot: Snapshot?
    let onLogin: () -> Void
    let onRefresh: () -> Void
    let onOpenWebPage: () -> Void

    public init(provider: any ProviderAdapter,
                snapshot: Snapshot?,
                onLogin: @escaping () -> Void,
                onRefresh: @escaping () -> Void,
                onOpenWebPage: @escaping () -> Void) {
        self.provider = provider
        self.snapshot = snapshot
        self.onLogin = onLogin
        self.onRefresh = onRefresh
        self.onOpenWebPage = onOpenWebPage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: provider.iconSystemName)
                Text(provider.displayName).bold()
                    .lineLimit(1)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.borderless)
            }
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
        .contextMenu {
            Button("打开网页", systemImage: "safari") {
                onOpenWebPage()
            }
        }
    }
}
