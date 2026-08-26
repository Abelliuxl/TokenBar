import CryptoKit
import Foundation

/// Minimal Alibaba Cloud BSS OpenAPI client used by the Bailian provider.
///
/// This intentionally implements the RPC signature locally so TokenBar does
/// not need a third-party SDK or a browser login flow just to read balance.
public enum AlibabaCloudBSSOpenAPI {
    private static let endpoint = "business.aliyuncs.com"
    private static let action = "QueryAccountBalance"
    private static let version = "2017-12-14"

    public static func fetchBalance(providerId: String,
                                    accessKeyId: String,
                                    accessKeySecret: String) async -> Snapshot {
        let parameters = commonParameters(accessKeyId: accessKeyId)
        let query = signedQuery(parameters: parameters, accessKeySecret: accessKeySecret)
        guard let url = URL(string: "https://\(endpoint)/?\(query)") else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 地址无效"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        AppLog.network.debug("[\(providerId)] Alibaba Cloud balance API request")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 未返回 HTTP 响应"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let reason = http.statusCode == 401 || http.statusCode == 403
                    ? "AccessKey 无效或无权查询账户余额"
                    : DiagnosticPreview.from(data)
                return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API HTTP \(http.statusCode)：\(reason)"))
            }
            return decode(data: data, providerId: providerId)
        } catch {
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 请求失败：\(error.localizedDescription)"))
        }
    }

    static func decode(data: Data, providerId: String = "bailian") -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 解析失败：\(DiagnosticPreview.from(data))"))
        }

        let success = root["Success"] as? Bool ?? false
        let code = stringValue(root["Code"])
        guard success, code == "200" else {
            let message = stringValue(root["Message"]) ?? "未知错误"
            let codeText = code.map { "Code=\($0)，" } ?? ""
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 返回错误：\(codeText)\(message)"))
        }

        guard let payload = root["Data"] as? [String: Any] else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 未返回账户数据"))
        }

        let currency = (stringValue(payload["Currency"]) ?? "CNY").uppercased()
        guard let amount = number(payload["AvailableCashAmount"] ?? payload["AvailableAmount"]), amount.isFinite else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("阿里云余额 API 未返回有效余额"))
        }

        let unit: String
        switch currency {
        case "CNY", "JPY": unit = "¥"
        case "USD": unit = "$"
        default: unit = currency
        }
        let label = currency == "CNY" ? "账户余额" : "账户余额 \(currency)"
        let quota = Quota(id: "balance-\(currency.lowercased())",
                          label: label,
                          used: 0,
                          total: amount,
                          unit: unit)
        return Snapshot(providerId: providerId, quotas: [quota], status: .ok)
    }

    private static func commonParameters(accessKeyId: String,
                                         now: Date = Date(),
                                         nonce: String = UUID().uuidString) -> [String: String] {
        [
            "AccessKeyId": accessKeyId,
            "Action": action,
            "Format": "JSON",
            "SignatureMethod": "HMAC-SHA1",
            "SignatureNonce": nonce,
            "SignatureVersion": "1.0",
            "Timestamp": timestampFormatter.string(from: now),
            "Version": version,
        ]
    }

    private static func signedQuery(parameters: [String: String], accessKeySecret: String) -> String {
        let canonical = canonicalQuery(parameters)
        let stringToSign = "GET&\(percentEncode("/"))&\(percentEncode(canonical))"
        let key = SymmetricKey(data: Data("\(accessKeySecret)&".utf8))
        let digest = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let signature = Data(digest).base64EncodedString()

        var signedParameters = parameters
        signedParameters["Signature"] = signature
        return canonicalQuery(signedParameters)
    }

    private static func canonicalQuery(_ parameters: [String: String]) -> String {
        parameters
            .sorted { lhs, rhs in
                lhs.key == rhs.key ? lhs.value < rhs.value : lhs.key < rhs.key
            }
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
