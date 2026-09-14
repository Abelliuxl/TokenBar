import Foundation

/// Adapter for ChatGPT/Codex plan usage.
///
/// Codex CLI no longer records rate-limit events in `~/.codex/sessions`, which
/// is what the original adapter scanned, so usage is read from the backend
/// behind <https://chatgpt.com/codex/cloud/settings/analytics#usage> instead.
///
/// - `cliToken` (default): reuses the ChatGPT login Codex CLI already stored in
///   `~/.codex/auth.json`, so the card keeps working with no extra login.
/// - `webSession`: reads the same endpoint from inside the logged-in WebKit
///   session, for machines where Codex CLI is not logged in.
///
/// See `docs/research/codex-research.md` for the endpoint notes.
public struct CodexAdapter: MultiModeProviderAdapter {
    public static let usagePageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!

    public let id = CodexUsageAPI.providerId
    public var displayName: String { "Codex" }
    public var iconSystemName: String { "terminal.fill" }
    public var brandIcon: BrandIcon? { .codex }
    public var loginURL: URL { Self.usagePageURL }

    public let defaultFetchModeId = CodexFetchMode.cliToken
    public let fetchModes = [
        ProviderFetchMode(id: CodexFetchMode.cliToken, title: "Codex 登录态"),
        ProviderFetchMode(id: CodexFetchMode.webSession, title: "网页登录"),
    ]

    private let webSession = HTTPAdapter(
        id: CodexUsageAPI.providerId,
        displayName: "Codex",
        iconSystemName: "terminal.fill",
        loginURL: CodexAdapter.usagePageURL,
        method: "GET",
        url: CodexUsageAPI.endpoint,
        headers: ["Accept": "application/json"],
        decoder: { data in CodexUsageAPI.snapshot(from: data) }
    )

    public init() {}

    public func fetch() async -> Snapshot {
        await CodexReadCache.shared.snapshot { await self.fetchUncached() }
    }

    private func fetchUncached() async -> Snapshot {
        guard ProviderFetchModeStore.selectedModeId(for: self) == CodexFetchMode.webSession else {
            return await fetchUsingCLILogin()
        }
        return await webSession.fetch()
    }

    /// Uses the ChatGPT login Codex CLI maintains locally. When that login is
    /// missing or rejected the browser session takes over, so a web login can
    /// keep the card alive without the user switching modes by hand.
    private func fetchUsingCLILogin() async -> Snapshot {
        guard let credentials = CodexAuthFile.load() else {
            return await webSessionFallback(reason: "未找到 Codex CLI 登录态 (~/.codex/auth.json)")
        }
        let snapshot = await CodexUsageAPI.fetch(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId
        )
        if case .needsRelogin = snapshot.status {
            return await webSessionFallback(reason: "Codex CLI 登录态已失效")
        }
        return snapshot
    }

    private func webSessionFallback(reason: String) async -> Snapshot {
        let webSnapshot = await webSession.fetch()
        if case .needsRelogin = webSnapshot.status {
            return Snapshot(providerId: id, quotas: [], status: .error(
                "\(reason)，网页登录态也不可用。请运行一次 codex 刷新登录，或在右键菜单选择“爬取模式 → 网页登录”后重新登录。"
            ))
        }
        return webSnapshot
    }
}

public enum CodexFetchMode {
    public static let cliToken = "cliToken"
    public static let webSession = "webSession"
}

/// Serializes Codex reads and avoids refetching for repeated clicks. The cache
/// is intentionally short-lived: a manual refresh always becomes eligible again
/// after five seconds.
actor CodexReadCache {
    static let shared = CodexReadCache()

    private let cooldown: TimeInterval
    private let clock: @Sendable () -> Date
    private var lastReadAt: Date?
    private var cachedSnapshot: Snapshot?

    init(cooldown: TimeInterval = 5, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.cooldown = cooldown
        self.clock = clock
    }

    func snapshot(_ read: @Sendable () -> Snapshot) -> Snapshot {
        if let cached = cachedSnapshotIfFresh() { return cached }

        let snapshot = read()
        lastReadAt = clock()
        cachedSnapshot = snapshot
        return snapshot
    }

    /// Async variant for the network fetch. Concurrent callers may still race
    /// into a duplicate request, but the poller already coalesces its ticks, so
    /// the cooldown only has to absorb rapid manual refreshes.
    func snapshot(_ read: @Sendable () async -> Snapshot) async -> Snapshot {
        if let cached = cachedSnapshotIfFresh() { return cached }

        let snapshot = await read()
        lastReadAt = clock()
        cachedSnapshot = snapshot
        return snapshot
    }

    private func cachedSnapshotIfFresh() -> Snapshot? {
        guard let lastReadAt, let cachedSnapshot,
              clock().timeIntervalSince(lastReadAt) < cooldown else {
            return nil
        }
        return cachedSnapshot
    }
}
