import Foundation

public struct ProvidersRegistry {
    public let adapters: [any ProviderAdapter]

    public static let `default` = ProvidersRegistry(adapters: [
        OpenCodeGoAdapter(),
        MinimaxAdapter(),
        SiliconFlowAdapter(),
        DeepSeekAdapter(),
        VolcanoEngineAdapter()
    ])

    public func enabled(_ store: SettingsStore = .init()) -> [any ProviderAdapter] {
        let enabledSet = store.enabledProviderIds
        if enabledSet.isEmpty { return adapters }
        return adapters.filter { enabledSet.contains($0.id) }
    }
}
