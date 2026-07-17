import Foundation

public actor Poller {
    private let appState: AppState
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private var isTicking = false
    private var refreshPending = false

    public init(appState: AppState, interval: TimeInterval = 300) {
        self.appState = appState
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        AppLog.poller.notice("Poller started (interval: \(self.interval)s)")
        DiagnosticLog.record("poller", "started; interval=\(Int(interval))s")
        task = Task { [weak self, interval] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.tickOnce()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        AppLog.poller.notice("Poller stopped")
        task?.cancel()
        task = nil
    }

    public func tickOnce() async {
        guard !isTicking else {
            AppLog.poller.notice("Tick skipped: previous tick still running")
            refreshPending = true
            DiagnosticLog.record("poller", "refresh queued; previous tick still running")
            return
        }
        isTicking = true
        defer {
            isTicking = false
            if refreshPending {
                refreshPending = false
                DiagnosticLog.record("poller", "running queued refresh")
                Task { await self.tickOnce() }
            }
        }

        // ProvidersRegistry.enabled() reads @AppStorage (MainActor-isolated),
        // so we hop to the main actor to compute the list of enabled adapters.
        let providers = await MainActor.run { ProvidersRegistry.default.enabled() }
        let tickID = String(UUID().uuidString.prefix(8))
        let startedAt = Date()
        DiagnosticLog.record("poller", "tick \(tickID) started; providers=\(providers.map(\.id).joined(separator: ","))")
        AppLog.poller.debug("Tick: \(providers.count) provider(s)")
        await withTaskGroup(of: Void.self) { group in
            for adapter in providers {
                group.addTask { [appState] in
                    let providerStartedAt = Date()
                    DiagnosticLog.record("poller", "tick \(tickID) provider \(adapter.id) started")
                    let snap = await adapter.fetch()
                    DiagnosticLog.record("poller", "tick \(tickID) provider \(adapter.id) finished; duration=\(String(format: "%.1f", Date().timeIntervalSince(providerStartedAt)))s quotas=\(snap.quotas.count)")
                    await appState.update(snapshot: snap)
                }
            }
        }
        AppLog.poller.debug("Tick done")
        DiagnosticLog.record("poller", "tick \(tickID) finished; duration=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
    }
}
