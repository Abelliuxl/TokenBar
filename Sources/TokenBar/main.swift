import AppKit

// Singleton guard (avoid two menu bar icons if launched twice)
let bundleId = "com.liuxiaoliang.tokenbar"
if let running = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == bundleId
}) && running.processIdentifier != getpid() {
    print("TokenBar is already running (pid=\(running.processIdentifier))")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()