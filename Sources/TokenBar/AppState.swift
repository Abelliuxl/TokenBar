import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var snapshots: [String: Snapshot] = [:]
    @Published public private(set) var lastError: String?

    public init() {}

    public func update(snapshot: Snapshot) {
        snapshots[snapshot.providerId] = snapshot
        if case .error(let msg) = snapshot.status {
            AppLog.network.error("[\(snapshot.providerId, privacy: .public)] fetch error: \(msg, privacy: .public)")
            DiagnosticLog.record("result", "provider=\(snapshot.providerId) status=error reason=\(msg)")
        } else if case .needsRelogin = snapshot.status {
            AppLog.network.notice("[\(snapshot.providerId, privacy: .public)] needs relogin")
            DiagnosticLog.record("result", "provider=\(snapshot.providerId) status=needsRelogin")
        } else {
            DiagnosticLog.record("result", "provider=\(snapshot.providerId) status=ok quotas=\(snapshot.quotas.count)")
        }
        if lastError != snapshot.providerId {
            AppLog.network.debug("[\(snapshot.providerId, privacy: .public)] updated → \(snapshot.quotas.count) quotas")
        }
    }

    public func clear(providerId: String) {
        snapshots.removeValue(forKey: providerId)
        AppLog.network.notice("[\(providerId)] cleared from state")
    }

    /// Aggregate health across all providers.
    /// `q.fraction` is `used / total`, so:
    ///   - fraction ≥ 0.95 → bumped to .danger
    ///   - fraction ≥ 0.80 → .warn (used ≥80% of total)
    ///   - any snapshot in `.needsRelogin` or `.error(...)` → .danger
    public var overallStatus: AggregateStatus {
        var worst: AggregateStatus = .ok
        let enabledProviderIds = SettingsStore().enabledProviderIds
        for snap in snapshots.values {
            guard enabledProviderIds.contains(snap.providerId) else { continue }
            for q in snap.quotas {
                if q.fraction >= 0.95 {
                    worst = max(worst, .danger)
                } else if q.fraction >= 0.80 {
                    worst = max(worst, .warn)
                }
            }
            if case .needsRelogin = snap.status { worst = max(worst, .danger) }
            if case .error = snap.status { worst = max(worst, .danger) }
        }
        return worst
    }
}

public enum AggregateStatus: Equatable, Comparable {
    case ok, warn, danger

    public static func < (lhs: AggregateStatus, rhs: AggregateStatus) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ s: AggregateStatus) -> Int {
        switch s {
        case .ok: return 0
        case .warn: return 1
        case .danger: return 2
        }
    }
}

extension AggregateStatus {
    /// `max` of two statuses using ordinal comparison.
    static func max(_ a: AggregateStatus, _ b: AggregateStatus) -> AggregateStatus {
        a >= b ? a : b
    }
}
