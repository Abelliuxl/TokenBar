import Foundation

public actor Poller {
    private let appState: AppState
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private var isTicking = false

    public init(appState: AppState, interval: TimeInterval = 300) {
        self.appState = appState
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        AppLog.poller.notice("Poller started (interval: \(self.interval)s)")
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
            return
        }
        isTicking = true
        defer { isTicking = false }

        // ProvidersRegistry.enabled() reads @AppStorage (MainActor-isolated),
        // so we hop to the main actor to compute the list of enabled adapters.
        let providers = await MainActor.run { ProvidersRegistry.default.enabled() }
        AppLog.poller.debug("Tick: \(providers.count) provider(s)")
        await withTaskGroup(of: Void.self) { group in
            for adapter in providers {
                group.addTask { [appState] in
                    let snap = await adapter.fetch()
                    await appState.update(snapshot: snap)
                }
            }
        }
        AppLog.poller.debug("Tick done")
    }
}
