import os

/// Centralized `os.log` loggers for the TokenBar app.
///
/// Usage:
///   AppLog.network.log("fetching \(url)")
///   AppLog.lifecycle.error("app crashed: \(error.localizedDescription)")
///
/// View logs in real time:
///   log stream --predicate 'subsystem=="com.liuxiaoliang.tokenbar"' --style compact
///
/// Or filter by category:
///   log stream --predicate 'subsystem=="com.liuxiaoliang.tokenbar" AND category=="network"'
public enum AppLog {
    private static let subsystem = "com.liuxiaoliang.tokenbar"

    /// App start/stop, lifecycle events
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    /// HTTP requests, responses, errors
    public static let network = Logger(subsystem: subsystem, category: "network")
    /// Login flow, cookie harvest
    public static let auth = Logger(subsystem: subsystem, category: "auth")
    /// Poller cycle
    public static let poller = Logger(subsystem: subsystem, category: "poller")
}
