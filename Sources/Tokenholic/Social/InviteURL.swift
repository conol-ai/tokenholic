import Foundation

/// Invite deep links. Reuses the already-registered `ai.conol.tokenholic://`
/// scheme (the OAuth redirect uses host `auth-callback`; invites use host
/// `invite`), so no new URL type is needed — only app-level routing in
/// `TokenholicApp` that branches on the host.
enum InviteURL {
    static let scheme = "ai.conol.tokenholic"
    static let host = "invite"

    static func make(code: String) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.queryItems = [URLQueryItem(name: "code", value: code)]
        return c.url
    }

    /// Pull a code out of a full invite URL.
    static func code(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// Accept either a pasted full link or a bare code; returns the code.
    static func extractCode(fromUserInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let code = code(from: url) { return code }
        return trimmed
    }
}
