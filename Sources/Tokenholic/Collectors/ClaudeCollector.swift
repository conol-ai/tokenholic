import Foundation

/// Canonical Claude Code data location on disk.
enum ClaudeDataLocation {
    static var projects: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }
}

/// Stateless full scan of `~/.claude/projects/**/*.jsonl`.
///
/// Used by the `--dump` CLI and as the `UsageCollector` reference. The app
/// itself uses `ClaudeUsageStore` for incremental rescans.
struct ClaudeCollector: UsageCollector {
    let tool: Tool = .claudeCode
    var projectsDirectory: URL = ClaudeDataLocation.projects

    func collect() throws -> [UsageRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDirectory.path),
              let enumerator = fm.enumerator(at: projectsDirectory, includingPropertiesForKeys: nil)
        else { return [] }

        var records: [UsageRecord] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            records.append(contentsOf: ClaudeParser.parseFile(at: url))
        }
        return records
    }
}
