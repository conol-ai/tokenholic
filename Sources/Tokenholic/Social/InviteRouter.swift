import Foundation
import AppKit
import SwiftUI

/// Routes `ai.conol.tokenholic://invite?code=…` deep links into the app.
///
/// The OAuth redirect (host `auth-callback`) is consumed by
/// `ASWebAuthenticationSession` and never reaches the app's `open` handler, so
/// only invite links arrive here. `redeem` is wired by `AppModel`; `openSocial`
/// is captured by the popover (which holds `openWindow`) so a click can surface
/// the Friends window. If the popover has never been shown, redemption still
/// runs — only the auto-open is best-effort.
@MainActor
enum InviteRouter {
    /// Wired by `AppModel.start()`. Setting it drains any code that arrived
    /// before AppModel existed (a URL-triggered cold launch).
    static var redeem: ((String) -> Void)? {
        didSet {
            if redeem != nil, let code = pendingCode {
                pendingCode = nil
                redeem?(code)
            }
        }
    }
    static var openSocial: (() -> Void)?
    private static var pendingCode: String?

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let code = InviteURL.code(from: url) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        openSocial?()
        if let redeem { redeem(code) } else { pendingCode = code }
        return true
    }
}

/// Minimal app delegate that delivers custom-scheme URLs (invite links) to the
/// router. Installed via `@NSApplicationDelegateAdaptor` in `TokenholicApp`.
final class TokenholicAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { InviteRouter.handle(url) }
        }
    }
}
