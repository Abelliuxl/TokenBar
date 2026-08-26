import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController {
    public let statusItem: NSStatusItem
    private var popover: NSPopover!
    private let appState: AppState
    private let poller: Poller
    private var cancellables = Set<AnyCancellable>()
    private let iconRenderer = IconRenderer()
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var didResignActiveObserver: NSObjectProtocol?

    public init(appState: AppState, poller: Poller) {
        self.appState = appState
        self.poller = poller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.button?.image = iconRenderer.image(for: .ok)

        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.contentSize = .init(width: 320, height: 480)
        self.popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(appState: appState,
                                         onRefresh: { [weak poller] in
                                             await poller?.tickOnce()
                                         }))

        self.statusItem.button?.action = #selector(togglePopover(_:))
        self.statusItem.button?.target = self
        installPopoverDismissalMonitors()

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

    private func installPopoverDismissalMonitors() {
        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }

        let mouseEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        // NSPopover's transient behavior does not reliably dismiss an accessory
        // app's popover when another window in the same app is clicked.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) {
            [weak self] event in
            self?.handleLocalMouseDown(event)
            return event
        }

        // A menu bar app may remain active while the user interacts with another
        // app. The global monitor covers that case as a second dismissal path.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard popover.isShown else { return }

        if let popoverWindow = popover.contentViewController?.viewIfLoaded?.window,
           event.window === popoverWindow {
            return
        }

        // Let the status item button receive its click so it can toggle the
        // popover normally. Any other click handled by this app dismisses it.
        if let button = statusItem.button,
           let buttonWindow = button.window,
           event.window === buttonWindow,
           let buttonSuperview = button.superview,
           button.frame.contains(buttonSuperview.convert(event.locationInWindow, from: nil)) {
            return
        }

        closePopover()
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let didResignActiveObserver {
            NotificationCenter.default.removeObserver(didResignActiveObserver)
        }
    }

    private func refreshIcon() {
        let status = appState.overallStatus
        statusItem.button?.image = iconRenderer.image(for: status)
    }
}
