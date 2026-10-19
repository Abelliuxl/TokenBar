import Foundation

public enum ProviderStatus: Sendable, Equatable {
    case ok
    /// The latest refresh failed, but the displayed quotas come from the last
    /// successful snapshot and are therefore intentionally stale.
    case stale(String)
    case needsRelogin
    case error(String)
}

/// How a quota reads at a glance: a consumption window belongs in a progress
/// bar, a balance belongs next to its amount. `nil` means "infer".
public enum QuotaPresentation: Sendable, Equatable {
    case usage
    case balance
}

public struct Quota: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let used: Double
    public let total: Double
    public let unit: String         // "%", "¥", "credits", …
    public let resetsAt: Date?
    public let resetText: String?
    public let presentation: QuotaPresentation?

    public init(id: String, label: String, used: Double, total: Double, unit: String,
                resetsAt: Date? = nil, resetText: String? = nil,
                presentation: QuotaPresentation? = nil) {
        self.id = id
        self.label = label
        self.used = used
        self.total = total
        self.unit = unit
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.presentation = presentation
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, used / total)
    }

    /// True for a consumption window that should be drawn as a progress bar.
    /// Balances are the inverse: they carry their amount instead of a ratio, so
    /// a balance drawn as a bar is always empty and therefore always wrong.
    public var showsProgressBar: Bool {
        switch presentation {
        case .usage: return true
        case .balance: return false
        case nil: return unit == "%" || used != 0
        }
    }

    /// A money balance in a currency TokenBar can label.
    public var isCurrency: Bool {
        !showsProgressBar && QuotaUnit.currencySymbol(for: unit) != nil
    }
}

/// Quota units reach TokenBar by being copied out of page text, so the same
/// currency arrives spelled several ways: "¥" (U+00A5) and "￥" (U+FFE5) are
/// different characters, and platforms also use "CNY", "RMB" or "元". Anything
/// that compares a unit must go through here first.
public enum QuotaUnit {
    /// Collapses different encodings of the *same* glyph. The probe copies the
    /// character the page rendered, so "￥" (U+FFE5) has to compare equal to
    /// "¥" (U+00A5) — that mismatch is what made yuan balances render as bars.
    public static func normalized(_ unit: String) -> String {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "￥": return "¥"
        case "＄": return "$"
        default: return unit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Canonical symbol to render a money amount with, or nil when the unit is
    /// not money. Currency words and ISO codes map onto their symbol; an
    /// unrecognised code (HKD, SGD…) is still money and keeps its own label.
    public static func currencySymbol(for unit: String) -> String? {
        let value = normalized(unit)
        switch value {
        case "¥", "$", "€", "£", "₩": return value
        case "元", "RMB", "CNY", "JPY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "KRW": return "₩"
        default:
            let scalars = value.unicodeScalars
            guard scalars.count == 3,
                  scalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
            return value
        }
    }

    /// Renders a balance for display: money keeps its symbol and two decimals,
    /// anything else (credits, tokens, a bare number) stays readable as-is.
    public static func displayAmount(_ value: Double, unit: String) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if let symbol = currencySymbol(for: trimmed) {
            return symbol + String(format: "%.2f", value)
        }
        let number = numberText(value)
        return trimmed.isEmpty ? number : "\(number) \(trimmed)"
    }

    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
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
    /// Real brand glyph for built-in providers; nil → UI falls back to `iconSystemName`.
    var brandIcon: BrandIcon? { get }
    /// Whether this provider exposes a browser login flow in the UI.
    var supportsWebLogin: Bool { get }
    /// Entry page user must log into (for webView providers) or the API base (for http providers).
    var loginURL: URL { get }
    /// Performs one fetch; must NEVER throw — return `.error(...)` instead.
    func fetch() async -> Snapshot
}

public extension ProviderAdapter {
    var brandIcon: BrandIcon? { nil }
    var supportsWebLogin: Bool { true }
}

public struct ProviderFetchMode: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let credentialFields: [ProviderCredentialField]

    public init(id: String, title: String, credentialFields: [ProviderCredentialField] = []) {
        self.id = id
        self.title = title
        self.credentialFields = credentialFields
    }
}

public struct ProviderCredentialField: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let placeholder: String
    public let isSecret: Bool

    public init(id: String, title: String, placeholder: String = "", isSecret: Bool = false) {
        self.id = id
        self.title = title
        self.placeholder = placeholder
        self.isSecret = isSecret
    }
}

/// Adopted by built-in providers that can obtain the same quota in more than one way.
/// The selected mode is persisted per provider by `ProviderFetchModeStore`.
public protocol MultiModeProviderAdapter: ProviderAdapter {
    var fetchModes: [ProviderFetchMode] { get }
    var defaultFetchModeId: String { get }
}

public enum ProviderFetchModeStore {
    public static func key(providerId: String) -> String { "tb.fetchMode.\(providerId)" }

    public static func selectedModeId(for provider: any MultiModeProviderAdapter) -> String {
        let saved = UserDefaults.standard.string(forKey: key(providerId: provider.id))
        return provider.fetchModes.contains(where: { $0.id == saved }) ? saved! : provider.defaultFetchModeId
    }

    public static func setSelectedModeId(_ modeId: String, providerId: String) {
        UserDefaults.standard.set(modeId, forKey: key(providerId: providerId))
    }
}

public enum DiagnosticPreview {
    public static func from(_ data: Data, limit: Int = 180) -> String {
        if let structured = structuredError(from: data) {
            return structured
        }
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]) + "..."
    }

    private static func structuredError(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let meta = obj["ResponseMetadata"] as? [String: Any],
           let error = meta["Error"] as? [String: Any] {
            let code = error["Code"] as? String
            let message = error["Message"] as? String
            let action = meta["Action"] as? String
            let pieces = [
                code.map { "Code=\($0)" },
                message.map { "Message=\($0)" },
                action.map { "Action=\($0)" },
            ].compactMap(\.self)
            if !pieces.isEmpty {
                return pieces.joined(separator: "; ")
            }
        }
        let message = (obj["message"] as? String)
            ?? (obj["msg"] as? String)
            ?? (obj["error_description"] as? String)
            ?? (obj["error"] as? String)
        if let message {
            let code = obj["code"].map { "Code=\($0); " } ?? ""
            return "\(code)Message=\(message)"
        }
        return nil
    }
}

public enum TextAmountParser {
    public static func cnyAmount(in text: String, near labels: [String]) -> Double? {
        currencyAmount(in: text, near: labels, prefixedSymbols: ["¥", "￥"], suffixedUnits: ["元", "CNY", "RMB"])
    }

    public static func usdAmount(in text: String, near labels: [String]) -> Double? {
        currencyAmount(in: text, near: labels, prefixedSymbols: ["$"], suffixedUnits: ["USD"])
    }

    private static func currencyAmount(in text: String, near labels: [String], prefixedSymbols: [String], suffixedUnits: [String]) -> Double? {
        for label in labels {
            guard let range = text.range(of: label, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let upper = range.upperBound
            let distance = text.distance(from: upper, to: text.endIndex)
            let end = text.index(upper, offsetBy: min(160, distance))
            if let amount = firstAmount(in: String(text[upper..<end]), allowBareNumber: true, prefixedSymbols: prefixedSymbols, suffixedUnits: suffixedUnits) {
                return amount
            }
        }
        return firstAmount(in: text, allowBareNumber: false, prefixedSymbols: prefixedSymbols, suffixedUnits: suffixedUnits)
    }

    private static func firstAmount(in text: String, allowBareNumber: Bool, prefixedSymbols: [String], suffixedUnits: [String]) -> Double? {
        let symbolClass = prefixedSymbols.map(NSRegularExpression.escapedPattern(for:)).joined()
        let unitGroup = suffixedUnits.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        var patterns = [
            #"["# + symbolClass + #"]\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#,
            #"([0-9][0-9,]*(?:\.[0-9]+)?)\s*(?:"# + unitGroup + #")"#
        ]
        if allowBareNumber {
            patterns.append(#"([0-9][0-9,]*(?:\.[0-9]+)?)"#)
        }
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            let raw = text[range].replacingOccurrences(of: ",", with: "")
            if let value = Double(raw) {
                return value
            }
        }
        return nil
    }
}
