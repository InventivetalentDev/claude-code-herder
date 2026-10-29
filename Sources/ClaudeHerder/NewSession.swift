import Foundation

/// Where a new session starts; mirrors the `cowclaude` shell function.
enum Workspace: Hashable {
    case repo
    case cow(URL)
    case newCow
}

/// Starts sessions by typing `cow` / `claude` into a new tab, so `cow.sh` stays the only
/// implementation of making a cow.
enum NewSession {
    /// Hardcoded for now: the monorepo is where all the Claude sessions live.
    static let repo = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Developer/tomatocake-dev")
    /// `cow` names the folder after the branch with `/` turned into `-` (`tommo-store`).
    static let branchPrefix = "tommo/"

    /// Cows cloned from `repo`, which `cow` keeps in a `cows` folder beside it.
    static func cows(of repo: URL) throws -> [URL] {
        let parent = repo.deletingLastPathComponent().appendingPathComponent("cows")
        guard FileManager.default.fileExists(atPath: parent.path) else {
            return []
        }
        let source = repo.standardizedFileURL.path
        return try FileManager.default
            .contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { dir in
                let marker = dir.appendingPathComponent(".git/cow-source")
                let recorded = try? String(contentsOf: marker, encoding: .utf8)
                return recorded?.trimmingCharacters(in: .whitespacesAndNewlines) == source
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Why a typed `name` can't be a new cow; nil if it can (or nothing is typed yet).
    static func problem(withName name: String, existing cows: [URL]) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard name.unicodeScalars.allSatisfy(allowed.contains), !name.hasPrefix("-"),
            !name.contains("..")
        else {
            return "Use lowercase letters, digits, - _ and ."
        }
        let folder = folderName(for: name)
        if cows.contains(where: { $0.lastPathComponent == folder }) {
            return "The \(folder) cow already exists; pick it on the first page."
        }
        return nil
    }

    static func folderName(for name: String) -> String {
        (branchPrefix + name).replacingOccurrences(of: "/", with: "-")
    }

    /// The folder the tab opens in and the line typed into it. The prompt is read from a file
    /// so quotes and newlines in it can't break the shell line.
    static func command(for workspace: Workspace, name: String, promptFile: URL)
        -> (directory: URL, input: String)
    {
        let file = shellQuoted(promptFile.path)
        let claude = "p=\"$(cat \(file))\" && rm \(file) && claude \"$p\""
        switch workspace {
        case .repo:
            return (repo, claude)
        case .cow(let dir):
            return (dir, claude)
        case .newCow:
            return (repo, "cow \(shellQuoted(branchPrefix + name)) && \(claude)")
        }
    }

    static func start(_ workspace: Workspace, name: String, prompt: String) async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-herder-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        let (directory, input) = command(for: workspace, name: name, promptFile: file)
        try await Ghostty.newTab(in: directory.path, typing: input)
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
