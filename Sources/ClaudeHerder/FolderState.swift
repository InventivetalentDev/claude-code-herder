import Foundation

/// What's left on disk of the folder a session ran in.
enum FolderState {
    /// A `cow` copy-on-write checkout that still exists.
    case liveCow
    /// Deleted (e.g. a cleaned-up cow), so `claude --resume` can't run there.
    case missing
    case present

    static func of(cwd: String?) -> FolderState {
        guard let cwd, FileManager.default.fileExists(atPath: cwd) else {
            return .missing
        }
        return Cows.root(containing: cwd) == nil ? .present : .liveCow
    }
}

/// Cows are checkouts made by the `cow` shell function, marked by `.git/cow-source`.
enum Cows {
    struct Status {
        let root: URL
        let branch: String
        let uncommittedFiles: Int
        /// Commits on HEAD that no remote-tracking branch has.
        let unpushedCommits: Int
    }

    /// The cow checkout `path` is inside, if any.
    static func root(containing path: String) -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path)
        while dir.pathComponents.count > 1 {
            if fm.fileExists(atPath: marker(of: dir).path) {
                return dir
            }
            // A repo root without the marker: an ordinary checkout, not a cow.
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return nil
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static func sessions(in root: URL, among sessions: [Session]) -> [Session] {
        sessions.filter { session in
            session.cwd.flatMap(Self.root(containing:))?.standardizedFileURL
                == root.standardizedFileURL
        }
    }

    static func status(of root: URL) async throws -> Status {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let branch = try await run(git, ["-C", root.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let changes = try await run(git, ["-C", root.path, "status", "--porcelain"])
        let unpushed = try await run(
            git, ["-C", root.path, "rev-list", "--count", "HEAD", "--not", "--remotes"])
        guard let unpushedCount = Int(unpushed.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CommandError(errorDescription: "git rev-list printed \(unpushed)")
        }
        return Status(
            root: root,
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            uncommittedFiles: changes.split(separator: "\n").count,
            unpushedCommits: unpushedCount)
    }

    /// Like `cow-destroy`: refuses anything that isn't marked as a cow.
    static func delete(_ root: URL) async throws {
        guard FileManager.default.fileExists(atPath: marker(of: root).path) else {
            throw CommandError(errorDescription: "\(root.path) has no .git/cow-source; not deleting it.")
        }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.removeItem(at: root)
        }.value
    }

    private static func marker(of dir: URL) -> URL {
        dir.appendingPathComponent(".git/cow-source")
    }
}
