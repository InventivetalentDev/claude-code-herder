import Foundation

/// Cows are copy-on-write checkouts made by the `cow` shell function, marked by `.git/cow-source`.
enum Cows {
    /// True if `cwd` is inside a cow checkout that still exists on disk.
    static func isInLiveCow(_ cwd: String) -> Bool {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd)
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
