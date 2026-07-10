import AppKit

public final class WebViewSessionManager {
    /// Retained while the login window is open so the controller isn't deallocated
    /// before the window closes and its callback fires.
    private var controller: LoginWindowController?

    public init() {}

    @MainActor
    public func startLogin(for provider: any ProviderAdapter,
                           onFieldRuleSelected: ((CustomFieldRule) -> Void)? = nil) async {
        await withCheckedContinuation { cont in
            let vc = LoginWindowController(provider: provider, onFinish: { [weak self] in
                self?.controller = nil  // release when done
                cont.resume()
            }, onFieldRuleSelected: onFieldRuleSelected)
            self.controller = vc
            vc.present()
        }
    }

    /// Open a persistent WebView for a new custom site and wait until the user
    /// either confirms a DOM/API field rule or closes the window.
    @MainActor
    public func startCustomProviderSetup(displayName: String, loginURL: URL) async -> CustomFieldRule? {
        await withCheckedContinuation { continuation in
            var completed = false
            weak var presentedController: LoginWindowController?

            let complete: (CustomFieldRule?) -> Void = { [weak self] rule in
                guard !completed else { return }
                completed = true
                presentedController?.close()
                self?.controller = nil
                continuation.resume(returning: rule)
            }

            let draft = CustomDraftProvider(displayName: displayName, loginURL: loginURL)
            let vc = LoginWindowController(
                provider: draft,
                onFinish: { complete(nil) },
                onFieldRuleSelected: { rule in complete(rule) }
            )
            presentedController = vc
            self.controller = vc
            vc.present()
        }
    }
}
