import Foundation

/// Whether the folder a session ran in is still on disk.
enum FolderState {
    /// Deleted (e.g. a cleaned-up worktree), so resuming can't run there.
    case missing
    case present

    static func of(cwd: String?) -> FolderState {
        guard let cwd, FileManager.default.fileExists(atPath: cwd) else {
            return .missing
        }
        return .present
    }
}
