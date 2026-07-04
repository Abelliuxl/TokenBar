import AppKit

public final class IconRenderer {
    private let cache: [AggregateStatus: NSImage]

    public init() {
        var c: [AggregateStatus: NSImage] = [:]
        c[.ok] = IconRenderer.load(name: "icon_green_512x512")
        c[.warn] = IconRenderer.load(name: "icon_yellow_512x512")
        c[.danger] = IconRenderer.load(name: "icon_red_512x512")
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
