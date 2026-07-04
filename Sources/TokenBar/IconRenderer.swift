import AppKit

public final class IconRenderer {
    private let cache: [AggregateStatus: NSImage]

    public init() {
        var c: [AggregateStatus: NSImage] = [:]
        // The status bar shows a single monochrome icon; tint color carries the status
        // (green/yellow/red). Loading is keyed by AggregateStatus so we could swap
        // to a colored icon per state later without changing the consumer.
        let base = IconRenderer.load(name: "icon_512x512")
        c[.ok] = base
        c[.warn] = base
        c[.danger] = base
        self.cache = c
    }

    public func image(for status: AggregateStatus) -> NSImage? {
        cache[status]
    }

    private static func load(name: String) -> NSImage? {
        if let img = NSImage(named: name) { return img }
        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
    }
}
