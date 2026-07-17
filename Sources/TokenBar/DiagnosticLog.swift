import Foundation

/// Opt-in, persistent diagnostics for issues that cannot be reproduced on demand.
/// This deliberately does not record cookies, response bodies, or page text.
public enum DiagnosticLog {
    public static let enabledKey = "tb.diagnosticLoggingEnabled"

    private static let queue = DispatchQueue(label: "com.liuxiaoliang.tokenbar.diagnostics")
    private static let maxFileSize: UInt64 = 2 * 1024 * 1024
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    public static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TokenBar/Diagnostics", isDirectory: true)
    }

    public static var fileURL: URL {
        directoryURL.appendingPathComponent("tokenbar-diagnostic.log")
    }

    public static func record(_ category: String, _ message: String) {
        guard isEnabled else { return }
        let timestamp = formatter.string(from: Date())
        let safeMessage = message.replacingOccurrences(of: "\n", with: " ")
        let line = "\(timestamp) [\(category)] \(safeMessage)\n"
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try rotateIfNeeded(adding: line.utf8.count)
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                // Diagnostics must never interfere with polling.
            }
        }
    }

    public static func enabled() {
        record("lifecycle", "diagnostic logging enabled; appVersion=\(AppVersion.display) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Keeps the useful host/path while avoiding tokens that may appear in a query or fragment.
    public static func safeURL(_ value: String?) -> String {
        guard let value, var components = URLComponents(string: value) else { return value ?? "<nil>" }
        components.query = nil
        components.fragment = nil
        return components.string ?? "<invalid-url>"
    }

    public static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: rotatedFileURL)
        }
    }

    private static var rotatedFileURL: URL {
        directoryURL.appendingPathComponent("tokenbar-diagnostic.previous.log")
    }

    private static func rotateIfNeeded(adding bytes: Int) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size + UInt64(bytes) > maxFileSize else { return }
        try? FileManager.default.removeItem(at: rotatedFileURL)
        try FileManager.default.moveItem(at: fileURL, to: rotatedFileURL)
    }
}
