import Foundation

public actor Poller {
    private let appState: AppState
    private var task: Task<Void, Never>?
    private let interval: TimeInterval

    public init(appState: AppState, interval: TimeInterval = 300) {
        self.appState = appState
        self.interval = interval
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self, interval] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.tickOnce()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func tickOnce() async {
        // ProvidersRegistry.enabled() reads @AppStorage (MainActor-isolated),
        // so we hop to the main actor to compute the list of enabled adapters.
        let providers = await MainActor.run { ProvidersRegistry.default.enabled() }
        await withTaskGroup(of: Void.self) { group in
            for adapter in providers {
                group.addTask { [appState] in
                    let snap = await adapter.fetch()
                    await appState.update(snapshot: snap)
                }
            }
        }
    }
}