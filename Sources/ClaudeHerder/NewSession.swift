import Foundation

/// Starts sessions by typing `claude` / `codex` into a new iTerm2 tab.
enum NewSession {
    /// The line typed into the tab. The prompt is read from a file so quotes and newlines in
    /// it can't break the shell line.
    static func command(for profile: Profile, promptFile: URL) -> String {
        let file = shellQuoted(promptFile.path)
        return "p=\"$(cat \(file))\" && rm \(file) && \(profile.command) \"$p\""
    }

    static func start(in directory: URL, profile: Profile, prompt: String) async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-herder-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        try await ITerm.newTab(in: directory.path, typing: command(for: profile, promptFile: file))
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
