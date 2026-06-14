import Foundation

/// A subscription-based AI coding tool that Tokenholic tracks.
///
/// v1 only feeds `.claudeCode`, but the pipeline is built to blend all of these.
enum Tool: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    /// API provider used to resolve pricing.
    var provider: String {
        switch self {
        case .claudeCode: return "anthropic"
        case .codex: return "openai"
        case .cursor: return "cursor"
        }
    }
}
