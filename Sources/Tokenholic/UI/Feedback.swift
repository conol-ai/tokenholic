import Foundation
import AppKit

/// Privacy-respecting feedback: opens a GitHub issue pre-filled with
/// non-sensitive environment facts the user can see and edit before submitting.
/// No telemetry, no backend — nothing leaves the machine unless the user clicks
/// "Submit" on GitHub.
enum Feedback {
    static let repo = "conol-ai/tokenholic"
    static let issuesURL = URL(string: "https://github.com/\(repo)/issues")!

    /// A pre-filled "new issue" URL. Includes app/OS versions and which log
    /// sources are detected — never prompt content, token counts, or PII.
    static func newIssueURL(hasUsage: Bool) -> URL? {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let fm = FileManager.default
        func mark(_ present: Bool) -> String { present ? "✓" : "○" }
        let claude = fm.fileExists(atPath: ClaudeDataLocation.projects.path)
        let codex  = fm.fileExists(atPath: CodexDataLocation.sessions.path)
        let gemini = fm.fileExists(atPath: GeminiDataLocation.telemetryLog)

        let body = """
        ### What's up?
        <!-- A bug, a reaction, or a tool you wish we supported — anything helps. -->


        ---
        _Environment (auto-filled — safe to edit; no prompts, token counts, or personal data):_
        - Tokenholic: v\(ver)
        - macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        - Detected logs: Claude Code \(mark(claude)) · Codex \(mark(codex)) · Gemini CLI \(mark(gemini))
        - Usage found this cycle: \(hasUsage ? "yes" : "no")
        """

        var comps = URLComponents(string: "https://github.com/\(repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "labels", value: "feedback"),
            URLQueryItem(name: "title", value: "Feedback: "),
            URLQueryItem(name: "body", value: body),
        ]
        return comps?.url
    }

    /// Opens the pre-filled issue in the user's browser (menubar-agent friendly).
    static func openNewIssue(hasUsage: Bool) {
        if let url = newIssueURL(hasUsage: hasUsage) { NSWorkspace.shared.open(url) }
    }
}
