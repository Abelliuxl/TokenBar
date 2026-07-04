import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController {
    public let statusItem: NSStatusItem
    private var popover: NSPopover!
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private let iconRenderer = IconRenderer()

    public init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.button?.image = iconRenderer.image(for: .ok)

        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.contentSize = .init(width: 320, height: 480)
        self.popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(appState: appState,
                                         onRefresh: { [weak appState] in
                                             Task { @MainActor in
                                                 guard let appState else { return }
                                                 await Poller(appState: appState).tickOnce()
                                             }
                                         }))

        self.statusItem.button?.action = #selector(togglePopover(_:))
        self.statusItem.button?.target = self

        appState.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refreshIcon() {
        let status = appState.overallStatus
        statusItem.button?.image = iconRenderer.image(for: status)
    }
}
