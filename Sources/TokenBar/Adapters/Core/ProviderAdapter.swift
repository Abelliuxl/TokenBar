import Foundation

public enum ProviderStatus: Sendable, Equatable {
    case ok
    case needsRelogin
    case error(String)
}

public enum FetchMode: Sendable {
    case http(method: String, url: String, headers: [String: String])
    case webView(url: String)
}

public struct Quota: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let used: Double
    public let total: Double
    public let unit: String         // "%" or "¥"
    public let resetsAt: Date?

    public init(id: String, label: String, used: Double, total: Double, unit: String, resetsAt: Date? = nil) {
        self.id = id
        self.label = label
        self.used = used
        self.total = total
        self.unit = unit
        self.resetsAt = resetsAt
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, used / total)
    }
}

public struct Snapshot: Sendable, Equatable {
    public let providerId: String
    public let capturedAt: Date
    public let quotas: [Quota]
    public let status: ProviderStatus

    public init(providerId: String, capturedAt: Date = .init(), quotas: [Quota], status: ProviderStatus) {
        self.providerId = providerId
        self.capturedAt = capturedAt
        self.quotas = quotas
        self.status = status
    }
}

public protocol ProviderAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconSystemName: String { get }
    /// Entry page user must log into (for webView providers) or the API base (for http providers).
    var loginURL: URL { get }
    /// Performs one fetch; must NEVER throw — return `.error(...)` instead.
    func fetch() async -> Snapshot
}