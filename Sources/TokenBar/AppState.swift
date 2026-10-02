import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var snapshots: [String: Snapshot] = [:]
    @Published public private(set) var lastError: String?

    public init() {}

    public func update(snapshot: Snapshot) {
        let storedSnapshot = staleSnapshotIfTransientFailure(snapshot)
        snapshots[storedSnapshot.providerId] = storedSnapshot
        switch storedSnapshot.status {
        case .error(let msg):
            AppLog.network.error("[\(storedSnapshot.providerId, privacy: .public)] fetch error: \(msg, privacy: .public)")
            DiagnosticLog.record("result", "provider=\(storedSnapshot.providerId) status=error reason=\(msg)")
        case .stale(let msg):
            AppLog.network.warning("[\(storedSnapshot.providerId, privacy: .public)] showing stale data after refresh error: \(msg, privacy: .public)")
            DiagnosticLog.record("result", "provider=\(storedSnapshot.providerId) status=stale reason=\(msg) quotas=\(storedSnapshot.quotas.count)")
        case .needsRelogin:
            AppLog.network.notice("[\(storedSnapshot.providerId, privacy: .public)] needs relogin")
            DiagnosticLog.record("result", "provider=\(storedSnapshot.providerId) status=needsRelogin")
        case .ok:
            DiagnosticLog.record("result", "provider=\(storedSnapshot.providerId) status=ok quotas=\(storedSnapshot.quotas.count)")
        }
        if lastError != storedSnapshot.providerId {
            AppLog.network.debug("[\(storedSnapshot.providerId, privacy: .public)] updated → \(storedSnapshot.quotas.count) quotas")
        }
    }

    private func staleSnapshotIfTransientFailure(_ snapshot: Snapshot) -> Snapshot {
        if snapshot.providerId == "command-code" {
            let ids = ["fiveHour", "weekly", "monthly"]
            switch snapshot.status {
            case .ok, .stale:
                if ids.contains(where: { id in !snapshot.quotas.contains { $0.id == id } }) {
                    let previous = snapshots[snapshot.providerId]
                    let merged = ids.compactMap { id in
                        if let current = snapshot.quotas.first(where: { $0.id == id }) { return current }
                        guard let old = previous?.quotas.first(where: { $0.id == id }) else { return nil }
                        let text = old.resetText?.replacingOccurrences(of: " · 上次数据", with: "") ?? ""
                        return Quota(id: old.id, label: old.label, used: old.used, total: old.total,
                                     unit: old.unit, resetsAt: old.resetsAt, resetText: text + " · 上次数据")
                    }
                    return Snapshot(providerId: snapshot.providerId, quotas: merged,
                                    status: .stale("部分额度未更新；缺失项保留上次数据"))
                }
            case .error(let message):
                if let previous = snapshots[snapshot.providerId], !previous.quotas.isEmpty {
                    return Snapshot(providerId: snapshot.providerId, capturedAt: previous.capturedAt,
                                    quotas: previous.quotas, status: .stale(message))
                }
            case .needsRelogin: break
            }
        }
        guard case .error(let message) = snapshot.status,
              Self.isTransientFailure(message),
              let previous = snapshots[snapshot.providerId],
              !previous.quotas.isEmpty else {
            return snapshot
        }

        switch previous.status {
        case .ok, .stale:
            return Snapshot(
                providerId: snapshot.providerId,
                capturedAt: previous.capturedAt,
                quotas: previous.quotas,
                status: .stale(message)
            )
        case .needsRelogin, .error:
            return snapshot
        }
    }

    private static func isTransientFailure(_ message: String) -> Bool {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "timeout" || value.hasPrefix("nav:")
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
            if case .stale = snap.status { worst = max(worst, .warn) }
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
