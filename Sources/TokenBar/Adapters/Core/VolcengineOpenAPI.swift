import Foundation
import CryptoKit

public enum VolcengineOpenAPI {
    public static func fetchBalance(providerId: String, accessKey: String, secretKey: String) async -> Snapshot {
        let host = "open.volcengineapi.com"
        let action = "QueryBalanceAcct"
        let version = "2022-01-01"
        let service = "billing"
        let region = "cn-north-1"
        let now = Date()
        let requestDate = utcFormatter("yyyyMMdd'T'HHmmss'Z'").string(from: now)
        let shortDate = utcFormatter("yyyyMMdd").string(from: now)
        let payloadHash = sha256Hex(Data())
        let canonicalQuery = "Action=\(action)&Version=\(version)"
        let canonicalHeaders = "host:\(host)\nx-content-sha256:\(payloadHash)\nx-date:\(requestDate)\n"
        let signedHeaders = "host;x-content-sha256;x-date"
        let canonicalRequest = "GET\n/\n\(canonicalQuery)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let scope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = "HMAC-SHA256\n\(requestDate)\n\(scope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"
        let kDate = hmac(key: Data(secretKey.utf8), message: Data(shortDate.utf8))
        let kRegion = hmac(key: kDate, message: Data(region.utf8))
        let kService = hmac(key: kRegion, message: Data(service.utf8))
        let kSigning = hmac(key: kService, message: Data("request".utf8))
        let signature = hmac(key: kSigning, message: Data(stringToSign.utf8)).hexString
        let authorization = "HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/"
        components.queryItems = [.init(name: "Action", value: action), .init(name: "Version", value: version)]
        guard let url = components.url else {
            return Snapshot(providerId: providerId, quotas: [], status: .error("开放 API 地址无效"))
        }
        var request = URLRequest(url: url)
        request.setValue(requestDate, forHTTPHeaderField: "X-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("开放 API 未返回 HTTP 响应"))
            }
            guard (200..<300).contains(http.statusCode) else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("开放 API HTTP \(http.statusCode): \(DiagnosticPreview.from(data))"))
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = obj["Result"] as? [String: Any],
                  let raw = result["AvailableBalance"] as? String,
                  let balance = Double(raw) else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("开放 API 解析失败: \(DiagnosticPreview.from(data))"))
            }
            return Snapshot(providerId: providerId, quotas: [Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")], status: .ok)
        } catch {
            return Snapshot(providerId: providerId, quotas: [], status: .error("开放 API 请求失败: \(error.localizedDescription)"))
        }
    }

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private static func sha256Hex(_ data: Data) -> String { Data(SHA256.hash(data: data)).hexString }
    private static func hmac(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
