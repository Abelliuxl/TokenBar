import SwiftUI

public struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    let onRefresh: () -> Void
    @State private var refreshing = false

    public init(appState: AppState, onRefresh: @escaping () -> Void) {
        self.appState = appState
        self.onRefresh = onRefresh
    }

    public var body: some View {
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
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ProvidersRegistry.default.adapters, id: \.id) { p in
                        ProviderSectionView(
                            provider: p,
                            snapshot: appState.snapshots[p.id],
                            onLogin: { Task { await loginFlow(for: p) } },
                            onRefresh: { onRefresh() }
                        )
                    }
                }
                .padding()
            }

            Divider()
            HStack {
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless)
                Spacer()
                Text("v0.1").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .frame(width: 320)
    }

    @MainActor
    private func loginFlow(for p: any ProviderAdapter) async {
        let mgr = WebViewSessionManager()
        if let blob = await mgr.startLogin(for: p) {
            try? KeychainStore().save(providerId: p.id, data: blob)
        }
        onRefresh()
    }
}
