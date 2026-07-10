import Foundation

public enum CustomFieldSource: String, Codable, Sendable {
    case dom
    case api
}

public struct CustomFieldRule: Codable, Sendable, Equatable {
    public let source: CustomFieldSource
    public let label: String
    public let unit: String
    public let valueKind: String
    public let domSelector: String?
    public let apiURL: String?
    public let apiMethod: String?
    public let apiBody: String?
    public let jsonPath: String?
    public let scale: Double

    public init(source: CustomFieldSource,
                label: String,
                unit: String,
                valueKind: String,
                domSelector: String? = nil,
                apiURL: String? = nil,
                apiMethod: String? = nil,
                apiBody: String? = nil,
                jsonPath: String? = nil,
                scale: Double = 1) {
        self.source = source
        self.label = label
        self.unit = unit
        self.valueKind = valueKind
        self.domSelector = domSelector
        self.apiURL = apiURL
        self.apiMethod = apiMethod
        self.apiBody = apiBody
        self.jsonPath = jsonPath
        self.scale = scale
    }
}

public struct CustomProviderDefinition: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let loginURL: String
    public let iconSystemName: String
    public let rule: CustomFieldRule

    public init(id: String = "custom-\(UUID().uuidString.lowercased())",
                displayName: String,
                loginURL: String,
                iconSystemName: String = "globe",
                rule: CustomFieldRule) {
        self.id = id
        self.displayName = displayName
        self.loginURL = loginURL
        self.iconSystemName = iconSystemName
        self.rule = rule
    }
}

public struct FieldCandidate: Codable, Sendable, Equatable, Identifiable {
    public let source: CustomFieldSource
    public let label: String
    public let preview: String
    public let score: Double
    public let selector: String?
    public let endpoint: String?
    public let method: String?
    public let body: String?
    public let jsonPath: String?
    public let valueKind: String
    public let unit: String

    public var id: String {
        let location = selector ?? "\(endpoint ?? "")#\(jsonPath ?? "")"
        return "\(source.rawValue):\(location):\(label)"
    }

    public var title: String {
        let prefix = source == .dom ? "页面" : "接口"
        let location = selector ?? "\(jsonPath ?? "字段")"
        let compactLocation = location.count > 54 ? String(location.prefix(51)) + "..." : location
        let compactPreview = preview.count > 46 ? String(preview.prefix(43)) + "..." : preview
        return "[\(prefix)] \(label.isEmpty ? compactLocation : label) — \(compactPreview)"
    }

    public func rule() -> CustomFieldRule {
        CustomFieldRule(
            source: source,
            label: label.isEmpty ? (source == .dom ? "页面余额" : "接口余额") : label,
            unit: unit,
            valueKind: valueKind,
            domSelector: selector,
            apiURL: endpoint,
            apiMethod: method,
            apiBody: body,
            jsonPath: jsonPath
        )
    }
}

public enum CustomProviderStore {
    public static let storageKey = "tb.customProviders"

    @MainActor
    public static func definitions() -> [CustomProviderDefinition] {
        guard let json = UserDefaults.standard.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([CustomProviderDefinition].self, from: data) else {
            return []
        }
        return values
    }

    @MainActor
    public static func save(_ definitions: [CustomProviderDefinition]) {
        guard let data = try? JSONEncoder().encode(definitions),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: storageKey)
    }

    @MainActor
    public static func upsert(_ definition: CustomProviderDefinition) {
        var values = definitions().filter { $0.id != definition.id }
        values.append(definition)
        save(values)
    }

    @MainActor
    public static func remove(id: String) {
        save(definitions().filter { $0.id != id })
    }
}

public struct CustomProviderAdapter: ProviderAdapter {
    public let id: String
    public let displayName: String
    public let iconSystemName: String
    public let loginURL: URL
    private let inner: any ProviderAdapter

    public init(definition: CustomProviderDefinition) {
        self.id = definition.id
        self.displayName = definition.displayName
        self.iconSystemName = definition.iconSystemName
        self.loginURL = URL(string: definition.loginURL) ?? URL(string: "about:blank")!

        switch definition.rule.source {
        case .dom:
            self.inner = CustomDOMAdapter(definition: definition)
        case .api:
            self.inner = CustomAPIAdapter(definition: definition)
        }
    }

    public func fetch() async -> Snapshot {
        await inner.fetch()
    }
}

private final class CustomDOMAdapter: WebViewAdapter {
    private let definition: CustomProviderDefinition

    init(definition: CustomProviderDefinition) {
        self.definition = definition
        let rule = definition.rule
        super.init(
            id: definition.id,
            displayName: definition.displayName,
            iconSystemName: definition.iconSystemName,
            loginURL: URL(string: definition.loginURL) ?? URL(string: "about:blank")!,
            harvestScript: CustomProviderRuntime.domHarvestScript(selector: rule.domSelector ?? "body")
        )
    }

    override func parse(harvest: Any?) -> Snapshot {
        guard let json = harvest as? String,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: definition.id, quotas: [], status: .error("自定义页面字段解析失败"))
        }
        guard let text = root["value"] as? String, !text.isEmpty else {
            let href = root["href"] as? String ?? ""
            if href.lowercased().contains("login") || href.lowercased().contains("signin") {
                return Snapshot(providerId: definition.id, quotas: [], status: .needsRelogin)
            }
            return Snapshot(providerId: definition.id, quotas: [], status: .error("页面中未找到已保存的字段"))
        }
        return CustomProviderRuntime.snapshot(providerId: definition.id, rule: definition.rule, text: text)
    }
}

private struct CustomAPIAdapter: ProviderAdapter {
    let id: String
    let displayName: String
    let iconSystemName: String
    let loginURL: URL
    private let inner: HTTPAdapter

    init(definition: CustomProviderDefinition) {
        self.id = definition.id
        self.displayName = definition.displayName
        self.iconSystemName = definition.iconSystemName
        self.loginURL = URL(string: definition.loginURL) ?? URL(string: "about:blank")!
        let rule = definition.rule
        let endpoint = URL(string: rule.apiURL ?? "") ?? self.loginURL
        var headers = ["Accept": "application/json"]
        if rule.apiBody != nil { headers["Content-Type"] = "application/json" }
        self.inner = HTTPAdapter(
            id: definition.id,
            displayName: definition.displayName,
            iconSystemName: definition.iconSystemName,
            loginURL: self.loginURL,
            method: rule.apiMethod ?? "GET",
            url: endpoint,
            headers: headers,
            body: rule.apiBody,
            decoder: { data in
                CustomProviderRuntime.apiSnapshot(providerId: definition.id, rule: rule, data: data)
            }
        )
    }

    func fetch() async -> Snapshot {
        await inner.fetch()
    }
}

public struct CustomDraftProvider: ProviderAdapter {
    public let id: String
    public let displayName: String
    public let iconSystemName = "globe"
    public let loginURL: URL

    public init(displayName: String, loginURL: URL) {
        self.id = "draft-\(UUID().uuidString.lowercased())"
        self.displayName = displayName
        self.loginURL = loginURL
    }

    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .error("自定义站点尚未保存字段规则"))
    }
}

public enum CustomProviderRuntime {
    public static func domHarvestScript(selector: String) -> String {
        let selectorJSON = jsString(selector)
        return """
        (function() {
          const el = document.querySelector(\(selectorJSON));
          return JSON.stringify({
            value: el ? (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim() : '',
            href: location.href,
            title: document.title || ''
          });
        })()
        """
    }

    public static func snapshot(providerId: String, rule: CustomFieldRule, text: String) -> Snapshot {
        let numbers = CustomProviderRuntime.numbers(in: text)
        let quota: Quota?
        switch rule.valueKind {
        case "percent":
            quota = numbers.first.map { Quota(id: "balance", label: rule.label, used: $0 * rule.scale, total: 100, unit: "%") }
        case "usedTotal":
            guard numbers.count >= 2 else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("自定义字段缺少已用/总额"))
            }
            quota = Quota(id: "balance", label: rule.label, used: numbers[0] * rule.scale, total: numbers[1] * rule.scale, unit: rule.unit)
        default:
            quota = numbers.first.map { Quota(id: "balance", label: rule.label, used: 0, total: $0 * rule.scale, unit: rule.unit) }
        }
        guard let quota else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("自定义字段中未找到数字"))
        }
        return Snapshot(providerId: providerId, quotas: [quota], status: .ok)
    }

    public static func apiSnapshot(providerId: String, rule: CustomFieldRule, data: Data) -> Snapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let value = jsonValue(object, path: rule.jsonPath ?? "") else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("自定义接口字段解析失败"))
        }
        let text: String
        if let string = value as? String {
            text = string
        } else if let number = value as? NSNumber {
            text = number.stringValue
        } else {
            text = String(describing: value)
        }
        return snapshot(providerId: providerId, rule: rule, text: text)
    }

    public static func jsonValue(_ root: Any, path: String) -> Any? {
        guard !path.isEmpty else { return root }
        var current: Any = root
        for component in path.split(separator: ".") {
            if let object = current as? [String: Any], let next = object[String(component)] {
                current = next
            } else if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    public static func numbers(in text: String) -> [Double] {
        let pattern = #"(?<![A-Za-z])(?:[¥￥$€]\s*)?([0-9][0-9,]*(?:\.[0-9]+)?)(?:\s*(?:元|CNY|RMB|USD|tokens?|credits?|%))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[valueRange].replacingOccurrences(of: ",", with: ""))
        }
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }
}
