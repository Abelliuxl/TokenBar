import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var snapshots: [String: Snapshot] = [:]
    @Published public private(set) var lastError: String?

    public init() {}

    public func update(snapshot: Snapshot) {
        snapshots[snapshot.providerId] = snapshot
    }

    public func clear(providerId: String) {
        snapshots.removeValue(forKey: providerId)
    }

    /// Aggregate health: .ok / .warn (any quota ≤ 20%) / .danger (any ≤ 5% or needsRelogin)
    public var overallStatus: AggregateStatus {
        var worst: AggregateStatus = .ok
        for snap in snapshots.values {
            for q in snap.quotas {
                if q.fraction >= 0.95 { worst = .danger(max(worst, .warn)); continue }
                if q.fraction >= 0.80 { worst = max(worst, .warn) }
            }
            if case .needsRelogin = snap.status { worst = .danger(worst) }
            if case .error = snap.status { worst = .danger(worst) }
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
        switch s { case .ok: return 0; case .warn: return 1; case .danger: return 2 }
    }
    static func max(_ a: AggregateStatus, _ b: AggregateStatus) -> AggregateStatus { a >= b ? a : b }
    static func danger(_ other: AggregateStatus) -> AggregateStatus { .danger }
}
