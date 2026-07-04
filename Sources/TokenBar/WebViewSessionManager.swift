import AppKit

public final class WebViewSessionManager {
    public init() {}

    @MainActor
    public func startLogin(for provider: any ProviderAdapter) async -> Data? {
        await withCheckedContinuation { cont in
            let vc = LoginWindowController(provider: provider) { blob in
                cont.resume(returning: blob)
            }
            vc.present()
            // The continuation resumes when the window is closed (via windowWillClose → onFinish).
        }
    }
}