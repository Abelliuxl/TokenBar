import Foundation
import Darwin
import Security

// MARK: - Argument parsing

struct Args {
    var provider: String = "unknown"
    var url: String = "https://example.com"
    var port: Int = 9222
    var host: String = "localhost"
    var verbose: Bool = false
    var extractCookies: Bool = false
}

func parseArgs() -> Args {
    var args = Args()
    let raw = CommandLine.arguments.dropFirst()
    var iter = raw.makeIterator()
    while let flag = iter.next() {
        switch flag {
        case "--provider":       args.provider = iter.next() ?? args.provider
        case "--url":            args.url = iter.next() ?? args.url
        case "--port":           args.port = Int(iter.next() ?? "") ?? args.port
        case "--host":           args.host = iter.next() ?? args.host
        case "--verbose":        args.verbose = true
        case "-v":               args.verbose = true
        case "--extract-cookies": args.extractCookies = true
        default: break
        }
    }
    return args
}

// MARK: - Keychain helpers

private let keychainService = "com.liuxiaoliang.tokenbar"

/// Save cookies (as a JSON array of `{name, value, domain}` objects) to the
/// macOS Keychain so TokenBar can read them.
func saveCookiesToKeychain(providerId: String, cookies: [[String: String]]) -> Bool {
    guard let data = try? JSONSerialization.data(withJSONObject: cookies, options: []) else {
        print("❌ Failed to serialize cookies")
        return false
    }

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: providerId,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    // Upsert: delete existing first
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecSuccess {
        print("✅ Saved \(cookies.count) cookie(s) for '\(providerId)' to Keychain")
        return true
    } else {
        print("❌ Keychain save failed: osstatus \(status)")
        return false
    }
}

/// Extract cookies for `urls` from Chrome via CDP and save them to the Keychain.
func extractCookies(client: CDPClient, providerId: String, urls: [String]) async throws {
    print("📡 Requesting cookies for \(urls.count) URL(s)...")

    let result = try await client.send("Network.getCookies", params: ["urls": urls])
    guard let cookies = result?["cookies"] as? [[String: Any]] else {
        print("❌ No cookies returned from Chrome")
        return
    }

    // Extract name, value, domain for each cookie
    let simplified = cookies.map { c -> [String: String] in
        var entry = [String: String]()
        entry["name"] = c["name"] as? String ?? ""
        entry["value"] = c["value"] as? String ?? ""
        entry["domain"] = c["domain"] as? String ?? ""
        return entry
    }

    print("🍪 Found \(simplified.count) cookie(s) for \(urls.joined(separator: ", "))")
    if simplified.isEmpty {
        print("⚠️  No cookies found. Make sure you are logged into this provider in Chrome.")
        return
    }

    let ok = saveCookiesToKeychain(providerId: providerId, cookies: simplified)
    if ok {
        print()
        print("   ✅ TokenBar will now use these cookies when fetching data for '\(providerId)'.")
        print("   📌 Launch the app and the data should appear.")
    }
}

// MARK: - Signals (Ctrl+C)

import Foundation
#if canImport(Darwin)
import Darwin
typealias SignalHandler = @convention(c) (Int32) -> Void
#endif

// We'll use DispatchSourceSignal for clean Ctrl+C handling.
// We'll use DispatchSourceSignal for clean Ctrl+C handling.
// The source must be retained to keep the handler active.
var signalSource: DispatchSourceSignal?

func installSignalHandler(_ handler: @escaping () -> Void) {
    let source = DispatchSource.makeSignalSource(signal: SIGINT)
    source.setEventHandler { handler() }
    source.resume()
    signalSource = source
    signal(SIGINT, SIG_IGN)
}

// MARK: - Balance field scanner

/// Keywords that suggest a JSON key contains balance/quota information.
private let balanceKeywords: Set<String> = [
    // English
    "balance", "balances",
    "quota", "quotas",
    "credit", "credits",
    "amount", "amounts",
    "remaining", "remain",
    "available",
    "used", "usage",
    "total",
    "token", "tokens",
    "spend", "spending",
    "billing",
    "subscription",
    // Chinese
    "余额", "额度", "已用", "剩余", "总量",
    "已使用", "可用额度", "总配额",
]

private let currencyPatterns: [String] = ["¥", "$", "cny", "usd", "tokens", "credits", "元"]

/// Field match result.
struct FieldMatch: Sendable {
    let key: String
    let value: String
}

/// Recursively scan a JSON value for balance-related fields.
/// Returns all matched key-value pairs.
func scanForBalance(_ value: Any, depth: Int = 0, prefix: String = "") -> [FieldMatch] {
    guard depth < 8 else { return [] } // limit recursion
    var matches: [FieldMatch] = []

    switch value {
    case let dict as [String: Any]:
        for (k, v) in dict {
            let fullKey = prefix.isEmpty ? k : "\(prefix).\(k)"
            let lowerKey = k.lowercased()

            // Check key name against keywords
            let keyMatched = balanceKeywords.contains { kw in
                lowerKey == kw || lowerKey.hasPrefix(kw) || lowerKey.contains("_\(kw)")
            }

            if keyMatched {
                matches.append(FieldMatch(key: fullKey, value: describe(v)))
            }

            // Check string values for currency/unit hints
            if let str = v as? String {
                let lowerStr = str.lowercased()
                for pat in currencyPatterns {
                    if lowerStr.contains(pat.lowercased()) {
                        // Found a currency marker — record the parent key context
                        matches.append(FieldMatch(key: fullKey, value: str))
                        break
                    }
                }
            }

            // Recurse into nested objects
            matches.append(contentsOf: scanForBalance(v, depth: depth + 1, prefix: fullKey))
        }
    case let arr as [[String: Any]]:
        for (i, item) in arr.enumerated() {
            matches.append(contentsOf: scanForBalance(item, depth: depth + 1, prefix: "\(prefix)[\(i)]"))
        }
    default:
        break
    }

    return matches
}

private func describe(_ value: Any) -> String {
    if let num = value as? NSNumber {
        // Check if it's a decimal or integer
        if CFNumberGetType(num) == .floatType || CFNumberGetType(num) == .doubleType {
            return String(format: "%.4f", num.doubleValue)
        }
        return "\(num.intValue)"
    }
    return "\(value)"
}

// MARK: - Response store

struct ResponseInfo: Sendable {
    let requestId: String
    let url: String
    let method: String
    let statusCode: Int
    let mimeType: String
    let startedAt: Date
}

struct MatchedResponse: Sendable {
    let info: ResponseInfo
    let body: String
    let matches: [FieldMatch]
}

// MARK: - Main

@main
@MainActor
enum InspectorMain {
    static func main() async {
        // Disable stdout buffering so piped output appears immediately.
        setlinebuf(stdout)

        let args = parseArgs()

        print("""
        ┌──────────────────────────────────────────────────┐
        │  🔍 Recon Inspector — Chrome DevTools Protocol   │
        │  Provider: \(args.provider.padding(toLength: 24, withPad: " ", startingAt: 0))
        │  URL:      \(args.url.padding(toLength: 24, withPad: " ", startingAt: 0))
        │  Port:     \(String(args.port).padding(toLength: 24, withPad: " ", startingAt: 0))
        │  Press Ctrl+C to stop and see report              │
        └──────────────────────────────────────────────────┘
        """)

        // Step 1: Verify Chrome is running
        let probeURL = URL(string: "http://\(args.host):\(args.port)/json/version")!
        do {
            let (_, resp) = try await URLSession.shared.data(from: probeURL)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
                print("❌ Chrome not reachable on \(args.host):\(args.port)")
                print()
                print("Start Chrome with remote debugging enabled:")
                print("  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=\(args.port)")
                print()
                print("Or if Chrome is already running, quit and restart with that flag.")
                exit(1)
            }
        } catch {
            print("❌ Cannot connect to Chrome at \(args.host):\(args.port)")
            print()
            print("Make sure Chrome is running with remote debugging enabled:")
            print("  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=\(args.port)")
            print()
            exit(1)
        }

        // Step 2: Connect via CDP
        let client = CDPClient()
        do {
            try await client.connectAsync(host: args.host, port: args.port)
            print("✅ Connected to Chrome.")
            // Navigate to the target URL if different from current page
            if args.url != "https://example.com" {
                print("   Navigating to \(args.url)...")
                try await client.send("Page.navigate", params: ["url": args.url])
            }
            print("   All network traffic is being monitored. Log in and browse to the billing page.\n")
        } catch {
            print("❌ Failed to connect: \(error.localizedDescription)")
            exit(1)
        }

        // Step 3: Monitor network traffic
        var allRequests: [String: ResponseInfo] = [:]
        var matchedResponses: [MatchedResponse] = []
        var requestCount = 0
        var stopRequested = false

        // Ctrl+C handler — must retain signalSource to keep the handler alive.
        installSignalHandler {
            stopRequested = true
            client.disconnect() // ends the event stream so the loop exits
        }

        let startedAt = Date()

        for await event in client.events {
            if stopRequested { break }

            switch event.method {
            case "Network.responseReceived":
                let params = event.params
                guard let response = params["response"] as? [String: Any],
                      let requestId = params["requestId"] as? String,
                      let url = response["url"] as? String,
                      let statusCode = response["status"] as? Int,
                      let mimeType = response["mimeType"] as? String else {
                    continue
                }
                let reqHeaders = response["requestHeaders"] as? [String: String]
                let httpMethod = reqHeaders?[":method"] ?? reqHeaders?["Method"] ?? "GET"

                // Only care about successful JSON responses (not images, fonts, etc.)
                guard statusCode >= 200 && statusCode < 300,
                      (mimeType.contains("json") || url.contains("/api/") || url.contains("/billing") || url.contains("/balance") || args.verbose) else {
                    if args.verbose {
                        print("[\(timestamp())] 📡 \(httpMethod) \(shortURL(url)) → \(statusCode) (\(mimeType))")
                    }
                    continue
                }

                let info = ResponseInfo(
                    requestId: requestId,
                    url: url,
                    method: httpMethod,
                    statusCode: statusCode,
                    mimeType: mimeType,
                    startedAt: Date()
                )
                allRequests[requestId] = info

            case "Network.loadingFinished":
                let params = event.params
                guard let requestId = params["requestId"] as? String,
                      let info = allRequests[requestId] else {
                    continue
                }
                requestCount += 1

                // Fetch the response body
                let bodyResult = try? await client.send("Network.getResponseBody",
                    params: ["requestId": requestId])
                guard let result = bodyResult,
                      let body = result["body"] as? String else {
                    if args.verbose {
                        print("[\(timestamp())] ⚠️ \(info.method) \(shortURL(info.url)) — body unavailable")
                    }
                    continue
                }
                let isBase64 = result["base64Encoded"] as? Bool ?? false
                let decodedBody: String
                if isBase64, let data = Data(base64Encoded: body) {
                    decodedBody = String(data: data, encoding: .utf8) ?? body
                } else {
                    decodedBody = body
                }

                // Parse JSON and scan for balance fields
                guard let jsonData = decodedBody.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) else {
                    continue
                }

                let fields = scanForBalance(json)
                let isUrlMatch = info.url.lowercased().contains("balance")
                    || info.url.lowercased().contains("quota")
                    || info.url.lowercased().contains("billing")
                    || info.url.lowercased().contains("usage")
                    || info.url.lowercased().contains("credit")

                let isShort = decodedBody.count < 2000

                if !fields.isEmpty || isUrlMatch || args.verbose {
                    // Print real-time match
                    let marker = fields.isEmpty ? "ℹ️" : "⚡"
                    let reason = fields.isEmpty ? " (URL matched billing/balance pattern)" : ""
                    print("[\(timestamp())] \(marker) \(info.method) \(shortURL(info.url)) → \(info.statusCode)\(reason)")

                    if !fields.isEmpty {
                        // Print matched fields in a compact format
                        let uniqueKeys = Set(fields.map { "\($0.key) = \($0.value)" })
                        for line in uniqueKeys.prefix(8) {
                            print("     📊 \(line)")
                        }
                        if uniqueKeys.count > 8 {
                            print("     ... and \(uniqueKeys.count - 8) more fields")
                        }

                        // Print the full JSON if it's short enough
                        if isShort {
                            // Pretty-print
                            if let data = decodedBody.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: data),
                               let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                               let pretty = String(data: prettyData, encoding: .utf8) {
                                for line in pretty.split(separator: "\n") {
                                    print("       \(line)")
                                }
                            } else {
                                print("       \(decodedBody)")
                            }
                        }
                        print()
                    } else if isShort && args.verbose {
                        if let data = decodedBody.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data),
                           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                           let pretty = String(data: prettyData, encoding: .utf8) {
                            for line in pretty.split(separator: "\n") {
                                print("       \(line)")
                            }
                        }
                        print()
                    }

                    let matched = MatchedResponse(info: info, body: decodedBody, matches: fields)
                    matchedResponses.append(matched)
                }

            case "Page.frameNavigated":
                let params = event.params
                guard let frame = params["frame"] as? [String: Any],
                      let url = frame["url"] as? String else {
                    continue
                }
                if url != "about:blank" {
                    print("[\(timestamp())] 🧭 Navigated to: \(url)\n")
                }

            default:
                // Suppress noisy internal events unless --verbose
                break
            }
        }

        // Step 4: Print final report
        printReport(
            provider: args.provider,
            url: args.url,
            startedAt: startedAt,
            requestCount: requestCount,
            matchedResponses: matchedResponses
        )

        client.disconnect()
    }
}

// MARK: - Helpers

func timestamp() -> String {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    return df.string(from: Date())
}

func shortURL(_ url: String) -> String {
    // Strip protocol and trailing slashes for readability
    var s = url
    if let range = s.range(of: "://") {
        s = String(s[range.upperBound...])
    }
    if s.hasSuffix("/") { s = String(s.dropLast()) }
    return s
}

// MARK: - Report

func printReport(provider: String, url: String, startedAt: Date, requestCount: Int, matchedResponses: [MatchedResponse]) {
    // Filter to only responses with actual field matches
    let withMatches = matchedResponses.filter { !$0.matches.isEmpty }

    print()
    print("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
    print("┃  📋 Report for \(provider.padding(toLength: 35, withPad: " ", startingAt: 0)) ┃")
    print("┃  URL: \(url.padding(toLength: 47, withPad: " ", startingAt: 0)) ┃")
    print("┃  Duration: \(Int(-startedAt.timeIntervalSinceNow))s  |  Requests: \(requestCount)  |  Matched: \(withMatches.count)  ┃")
    print("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
    print()

    guard !withMatches.isEmpty else {
        print("⚠️  No responses with balance/quota fields detected.")
        print()
        print("Suggestions:")
        print("  1. Make sure you're logged in and on the billing/dashboard page")
        print("  2. Try reloading the page (Cmd+R) to trigger API calls")
        print("  3. Some sites use GraphQL — check the Network tab manually")
        print("  4. Use --verbose to see all JSON responses")
        print()
        return
    }

    // Group by URL for cleaner output
    var grouped: [String: [MatchedResponse]] = [:]
    for mr in withMatches {
        grouped[mr.info.url, default: []].append(mr)
    }

    // Sort: responses with more matches first, then by URL
    let sorted = grouped.sorted { lhs, rhs in
        let lScore = lhs.value.reduce(0) { $0 + $1.matches.count }
        let rScore = rhs.value.reduce(0) { $0 + $1.matches.count }
        if lScore != rScore { return lScore > rScore }
        return lhs.key < rhs.key
    }

    print("Top matched endpoints:")
    print()

    for (url, responses) in sorted {
        let allMatches = responses.flatMap(\.matches)
        let uniqueFields = Dictionary(grouping: allMatches) { $0.key }
            .mapValues { $0.first!.value }
            .sorted { $0.key < $1.key }

        let first = responses.first!
        print("📍 \(first.info.method) \(url)")
        print("   Status: \(first.info.statusCode)  |  Type: \(first.info.mimeType)")
        print("   Matched \(uniqueFields.count) field(s):")

        for (key, val) in uniqueFields.prefix(10) {
            print("     📊 \(key) = \(val)")
        }
        if uniqueFields.count > 10 {
            print("     ... and \(uniqueFields.count - 10) more fields")
        }

        // Show a sample of the full JSON (truncated)
        if let sample = responses.first {
            let maxLen = 500
            let body = sample.body
            if body.count <= maxLen {
                print("   Body:")
                if let data = body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                   let pretty = String(data: prettyData, encoding: .utf8) {
                    for line in pretty.split(separator: "\n") {
                        print("     \(line)")
                    }
                }
            } else {
                print("   Body: \(body.count) chars (use --verbose to see full body)")
            }
        }
        print()
    }

    // Print recommendation section
    print("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓")
    print("┃  💡 Recommended Adapter Configuration                      ┃")
    print("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛")
    print()

    // For each unique URL with matches, suggest adapter configuration
    for (url, responses) in sorted {
        let allMatches = responses.flatMap(\.matches)
        let uniqueKeys = Set(allMatches.map(\.key))

        // Guess which key is the primary balance
        let primaryKey = uniqueKeys.first { key in
            let lower = key.lowercased()
            return lower == "balance" || lower.hasSuffix(".balance") || lower.contains("余额")
        }

        print("Endpoint: \(responses.first!.info.method) \(url)")
        print("Status: \(responses.first!.info.statusCode)")
        if let primary = primaryKey {
            print("Primary field: \(primary)")
        } else {
            print("Primary field: \(uniqueKeys.first ?? "???") (verify manually)")
        }
        if uniqueKeys.count > 1 {
            print("Other fields: \(uniqueKeys.sorted().joined(separator: ", "))")
        }
        print()
    }

    print("📝 Next steps:")
    print("  1. Copy the confirmed endpoint + field names into the research doc:")
    print("     docs/research/\(provider)-research.md")
    print("  2. Update the Adapter in Sources/TokenBar/Adapters/")
    print("  3. Rebuild and test with ./scripts/build.sh && ./scripts/smoke.sh")
    print()
}

// MARK: - String padding helper

private extension String {
    func padding(toLength length: Int, withPad pad: String, startingAt: Int) -> String {
        guard count < length else { return String(suffix(length)) }
        return self + String(repeating: pad, count: length - count)
    }
}
