import Foundation

/// Concrete `ProviderAdapter` that performs a single HTTP request (GET/POST),
/// loading a session cookie from the keychain and feeding the response body
/// to a caller-supplied decoder closure.
///
/// Concrete adapters (e.g. `SiliconFlowAdapter`) typically compose this with
/// their own thin wrapper struct that supplies `id` / `displayName` / etc.,
/// rather than subclassing — keeps this type `final` and `Sendable`.
public final class HTTPAdapter: ProviderAdapter {
    public let id: String
    public let displayName: String
    public let iconSystemName: String
    public let loginURL: URL
    public let method: String
    public let url: URL
    public let headers: [String: String]
    private let decoder: @Sendable (Data) -> Snapshot

    public init(id: String,
                displayName: String,
                iconSystemName: String,
                loginURL: URL,
                method: String,
                url: URL,
                headers: [String: String] = [:],
                decoder: @escaping @Sendable (Data) -> Snapshot) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.loginURL = loginURL
        self.method = method
        self.url = url
        self.headers = headers
        self.decoder = decoder
    }

    public func fetch() async -> Snapshot {
        do {
            let key = try KeychainStore().load(providerId: id)
            let cookieHeader = HTTPAdapter.cookieHeader(from: key) ?? ""
            var req = URLRequest(url: url)
            req.httpMethod = method
            if !cookieHeader.isEmpty {
                req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
            }
            return decoder(data)
        } catch {
            return Snapshot(providerId: id, quotas: [], status: .error("\(error)"))
        }
    }

    /// Parses a cookie blob from the keychain into a `Cookie:` header value.
    ///
    /// Accepts JSON of two shapes:
    ///   - `{"name":"session","value":"abc"}`
    ///   - `{"cookies":[{"name":"a","value":"b"}, ...]}`
    /// Returns nil if the blob is nil or unrecognised.
    public static func cookieHeader(from blob: Data?) -> String? {
        guard let blob,
              let json = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] else {
            return nil
        }
        if let name = json["name"] as? String,
           let value = json["value"] as? String {
            return "\(name)=\(value)"
        }
        if let arr = json["cookies"] as? [[String: String]] {
            let parts = arr.compactMap { kv -> String? in
                if let n = kv["name"], let v = kv["value"] { return "\(n)=\(v)" }
                return nil
            }
            return parts.isEmpty ? nil : parts.joined(separator: "; ")
        }
        return nil
    }
}