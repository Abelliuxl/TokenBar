import Foundation

public struct ProvidersRegistry {
    public let adapters: [any ProviderAdapter]

    public static let `default` = ProvidersRegistry(adapters: [
        OpenCodeGoAdapter(),
        MinimaxAdapter(),
        SiliconFlowAdapter(),
        DeepSeekAdapter(),
        VolcanoEngineAdapter(),
        OpenRouterAdapter(),
        CodexAdapter()
    ])

    @MainActor
    public func enabled(_ store: SettingsStore = .init()) -> [any ProviderAdapter] {
        let enabledSet = store.enabledProviderIds
        return ordered(store).filter { enabledSet.contains($0.id) }
    }

    @MainActor
    public func ordered(_ store: SettingsStore = .init()) -> [any ProviderAdapter] {
        let order = store.providerOrderIds
        guard !order.isEmpty else { return adapters }

        var byId = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
        var result: [any ProviderAdapter] = []
        for id in order {
            if let adapter = byId.removeValue(forKey: id) {
                result.append(adapter)
            }
        }
        result.append(contentsOf: adapters.filter { byId[$0.id] != nil })
        return result
    }
}
