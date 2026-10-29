import Darwin
import Foundation

/// Sessions currently running in some terminal, from Claude Code's live registry:
/// one `~/.claude/sessions/<pid>.json` per running process.
enum OpenSessions {
    static let registry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions")

    private struct Entry: Decodable {
        let pid: Int32
        let sessionId: String
        /// Milliseconds since 1970.
        let startedAt: Double
        let kind: String?
    }

    struct Result {
        /// Session ID to the PID of the Claude process running it.
        let pids: [String: Int32]
        let failures: [IndexFailure]
    }

    static func scan(_ dir: URL = registry) -> Result {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        } catch {
            return Result(pids: [:], failures: [IndexFailure(path: dir.path, message: "\(error)")])
        }
        var pids: [String: Int32] = [:]
        var failures: [IndexFailure] = []
        // Only the .json files; the .key files next to them are secrets we have no use for.
        for file in files where file.pathExtension == "json" {
            do {
                let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
                // Background jobs (`claude -p`, SDK) have no tab to point at.
                if entry.kind == "interactive", isRunning(entry) {
                    pids[entry.sessionId] = entry.pid
                }
            } catch {
                failures.append(IndexFailure(path: file.path, message: "\(error)"))
            }
        }
        return Result(pids: pids, failures: failures)
    }

    /// Files outlive crashed processes and PIDs get reused, so also check the start time.
    private static func isRunning(_ entry: Entry) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(entry.pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return false  // no such process
        }
        let started = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        return abs(started - entry.startedAt / 1000) < 60
    }
}
