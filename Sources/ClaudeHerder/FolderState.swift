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
        return isInCow(cwd) ? .liveCow : .present
    }

    /// Cows are made by the `cow` shell function, which marks them with `.git/cow-source`.
    static func isInCow(_ path: String) -> Bool {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path)
        while dir.pathComponents.count > 1 {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git/cow-source").path) {
                return true
            }
            // A repo root without the marker: an ordinary checkout, not a cow.
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return false
            }
            dir.deleteLastPathComponent()
        }
        return false
    }
}
