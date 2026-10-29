import Foundation

/// Where sessions live: a Claude Code config dir, or a Codex home.
struct Profile: Codable, Hashable, Identifiable {
    enum Tool: String, Codable {
        case claude, codex
    }

    let label: String
    let tool: Tool
    /// `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex.
    let home: URL
    /// Starts the tool under this profile, typed into an interactive shell.
    let command: String
    /// Badge color, as 0xRRGGBB.
    let color: UInt32

    /// The folder is what tells profiles apart; labels can repeat.
    var id: String { home.path }

    var isClaude: Bool {
        tool == .claude
    }

    /// Where the transcripts are: `<project>/<uuid>.jsonl` for Claude,
    /// `<yyyy>/<mm>/<dd>/rollout-*.jsonl[.zst]` for Codex.
    var transcriptRoots: [URL] {
        switch tool {
        case .claude: [home.appendingPathComponent("projects")]
        case .codex: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
        }
    }

    /// Claude Code's registry of running sessions. Codex keeps none.
    var registry: URL? {
        isClaude ? home.appendingPathComponent("sessions") : nil
    }

    func resumeCommand(sessionID: String) -> String {
        isClaude ? "\(command) --resume \(sessionID)" : "\(command) resume \(sessionID)"
    }
}

/// Profiles come from `~/.config/claude-herder/profiles.json` when it exists, else from the
/// Claude Code and Codex folders in the home folder (`~/.claude`, `~/.claude-*`, `~/.codex`).
enum ProfileConfig {
    struct Result {
        let profiles: [Profile]
        let failures: [IndexFailure]
    }

    /// One profile in `profiles.json`. Only `label` and `dir` are required.
    struct Entry: Decodable {
        let label: String
        /// Absolute, or starting with `~/`.
        let dir: String
        /// Defaults to `claude`.
        var tool: Profile.Tool? = nil
        /// Defaults to plain `claude` / `codex` for `~/.claude` / `~/.codex`, else to one that
        /// sets `CLAUDE_CONFIG_DIR` / `CODEX_HOME` to `dir`.
        var command: String? = nil
        /// `#RRGGBB`; defaults to the next color of a fixed palette.
        var color: String? = nil
    }

    private struct File: Decodable {
        let profiles: [Entry]
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-herder/profiles.json")

    private static let palette: [UInt32] = [0xD97757, 0x3B6EA8, 0x4F8A52, 0x7B5EA7, 0x2E8B8B]
    private static let codexColor: UInt32 = 0x5E5D59

    /// A broken config file is reported, and the app carries on with the discovered profiles.
    static func load(
        from url: URL = url, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Result(profiles: discover(in: home), failures: [])
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            return Result(profiles: try profiles(from: file.profiles, home: home), failures: [])
        } catch {
            return Result(
                profiles: discover(in: home),
                failures: [IndexFailure(path: url.path, message: "\(error)")])
        }
    }

    /// `~/.claude` as "Claude", `~/.claude-work` as "work", then `~/.codex` as "Codex". A Claude
    /// folder counts once it has `projects`, Codex once it has its state database.
    static func discover(in home: URL) -> [Profile] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home.path)) ?? []
        var entries = names
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .filter { fm.fileExists(atPath: home.appendingPathComponent("\($0)/projects").path) }
            .sorted()
            .map { name in
                Entry(label: name == ".claude" ? "Claude" : String(name.dropFirst(".claude-".count)), dir: "~/\(name)")
            }
        if (try? CodexIndex.database(in: home.appendingPathComponent(".codex"))) != nil {
            entries.append(Entry(label: "Codex", dir: "~/.codex", tool: .codex))
        }
        // Can't throw: the folders are distinct and there are no colors to parse.
        return (try? profiles(from: entries, home: home)) ?? []
    }

    static func profiles(from entries: [Entry], home: URL) throws -> [Profile] {
        var profiles: [Profile] = []
        var claudeCount = 0
        for entry in entries {
            let dir = expand(entry.dir, home: home)
            guard !profiles.contains(where: { $0.id == dir.path }) else {
                throw CommandError(errorDescription: "Two profiles use \(dir.path)")
            }
            let tool = entry.tool ?? .claude
            var color = tool == .codex ? codexColor : palette[claudeCount % palette.count]
            if tool == .claude {
                claudeCount += 1
            }
            if let hex = entry.color {
                guard hex.hasPrefix("#"), hex.count == 7, let parsed = UInt32(hex.dropFirst(), radix: 16) else {
                    throw CommandError(errorDescription: "\(entry.label): color \(hex) isn't #RRGGBB")
                }
                color = parsed
            }
            profiles.append(
                Profile(
                    label: entry.label, tool: tool, home: dir,
                    command: entry.command ?? defaultCommand(tool, dir: dir, home: home), color: color))
        }
        return profiles
    }

    private static func defaultCommand(_ tool: Profile.Tool, dir: URL, home: URL) -> String {
        switch tool {
        case .claude:
            dir.path == expand("~/.claude", home: home).path
                ? "claude" : "CLAUDE_CONFIG_DIR=\(NewSession.shellQuoted(dir.path)) claude"
        case .codex:
            dir.path == expand("~/.codex", home: home).path
                ? "codex" : "CODEX_HOME=\(NewSession.shellQuoted(dir.path)) codex"
        }
    }

    private static func expand(_ path: String, home: URL) -> URL {
        let url: URL
        if path == "~" {
            url = home
        } else if path.hasPrefix("~/") {
            url = home.appendingPathComponent(String(path.dropFirst(2)))
        } else {
            url = URL(fileURLWithPath: path, relativeTo: home).absoluteURL
        }
        // Without a trailing slash, so `path` compares equal however the folder was spelled.
        return URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: false)
    }
}
