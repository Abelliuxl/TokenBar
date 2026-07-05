import AppKit

public final class WebViewSessionManager {
    /// Retained while the login window is open so the controller isn't deallocated
    /// before the window closes and its callback fires.
    private var controller: LoginWindowController?

    public init() {}

    @MainActor
    public func startLogin(for provider: any ProviderAdapter) async {
        await withCheckedContinuation { cont in
            let vc = LoginWindowController(provider: provider) { [weak self] in
                self?.controller = nil  // release when done
                cont.resume()
            }
            self.controller = vc
            vc.present()
        }
    }
}
