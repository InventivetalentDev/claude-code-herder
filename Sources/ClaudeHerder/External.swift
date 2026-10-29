import Foundation

struct CommandError: LocalizedError {
    let errorDescription: String?
}

/// Full-text search over Claude and Codex transcripts by shelling out to ripgrep.
enum TranscriptSearch {
    /// Session IDs whose transcript (or subagent transcripts) contain every word of `query`.
    static func sessionIDs(
        matching query: String, in roots: [URL], codexParents: [String: String] = [:]
    ) async throws -> Set<String> {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let rg = try Tools.find("rg", formula: "ripgrep")
        // Without zstd on its PATH, ripgrep silently skips Codex's compressed rollouts.
        let zstd = try Tools.find("zstd", formula: "zstd")
        let environment = ["PATH": "\(zstd.deletingLastPathComponent().path):/usr/bin:/bin"]
        let roots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        // Given no paths, ripgrep would search the current directory instead.
        guard !roots.isEmpty else {
            return []
        }
        return try await withThrowingTaskGroup(of: Set<String>.self) { group in
            for word in words {
                group.addTask {
                    let files = try await filesMatching(
                        word: word, rg: rg, roots: roots, environment: environment)
                    return Set(files.map { sessionID(forTranscript: $0, codexParents: codexParents) })
                }
            }
            var matches: Set<String>?
            for try await ids in group {
                matches = matches?.intersection(ids) ?? ids
            }
            return matches ?? []
        }
    }

    private static func filesMatching(
        word: String, rg: URL, roots: [URL], environment: [String: String]
    ) async throws -> [URL] {
        // --count reads every file to the end. --files-with-matches stops at the first hit,
        // which kills zstd mid-write and drops that file with a "broken pipe" error.
        let args = [
            "--count", "--null", "--fixed-strings", "--ignore-case", "--no-ignore", "--search-zip",
            "--glob", "*.jsonl", "--glob", "*.jsonl.zst", "--", word,
        ] + roots.map(\.path)
        let output = try await run(rg, args, okExitCodes: [0, 1], environment: environment)  // 1 = no matches
        // Each line is `<path>\0<count>`.
        return output.split(separator: "\n").compactMap { line in
            line.split(separator: "\0", maxSplits: 1).first.map { URL(fileURLWithPath: String($0)) }
        }
    }

    static func sessionID(forTranscript url: URL, codexParents: [String: String]) -> String {
        let name = url.lastPathComponent
        // Codex: `rollout-<timestamp>-<uuid>.jsonl`, compressed to `.jsonl.zst` once old.
        // Subagents get their own rollout; they belong to the thread that spawned them.
        if name.hasPrefix("rollout-") {
            var stem = Substring(name)
            for ext in [".zst", ".jsonl"] where stem.hasSuffix(ext) {
                stem = stem.dropLast(ext.count)
            }
            return CodexIndex.rootThread(of: String(stem.suffix(36)), parents: codexParents)
        }
        // Claude subagent transcripts live in `<uuid>/subagents/`; they belong to `<uuid>`.
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" {
            return parent.deletingLastPathComponent().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// Command-line tools installed with Homebrew.
enum Tools {
    /// GUI apps don't inherit the shell PATH, so look in the usual install spots.
    static func find(_ name: String, formula: String) throws -> URL {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        guard let dir = dirs.first(where: { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") })
        else {
            throw CommandError(errorDescription: "\(name) not found; install it with `brew install \(formula)`")
        }
        return URL(fileURLWithPath: "\(dir)/\(name)")
    }
}

/// Opens and finds sessions in iTerm2 tabs, via iTerm2's AppleScript dictionary.
/// Addressed by bundle ID, since the app may be named "iTerm" or "iTerm2".
enum ITerm {
    private static let newTabScript = """
        on run argv
            set dir to item 1 of argv
            set cmd to item 2 of argv
            tell application id "com.googlecode.iterm2"
                activate
                if (count of windows) is 0 or current window is missing value then
                    set w to (create window with default profile)
                else
                    set w to current window
                    tell w to create tab with default profile
                end if
                tell current session of w to write text "cd " & quoted form of dir & " && " & cmd
            end tell
        end run
        """

    /// Finds the session on terminal `tty` and focuses or closes it.
    private static let sessionScript = """
        on run argv
            set target to item 1 of argv
            set action to item 2 of argv
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (tty of s) is target then
                                if action is "close" then
                                    close s
                                else
                                    select w
                                    select t
                                    select s
                                    activate
                                end if
                                return "found"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
        end run
        """

    /// Brings forward the tab running `pid` (a running Claude session).
    static func focus(pid: Int32) async throws {
        try await runOnSession(pid: pid, action: "focus")
    }

    /// Closes the tab running `pid` and waits for that Claude session to exit.
    static func close(pid: Int32) async throws {
        try await runOnSession(pid: pid, action: "close")
        // The process outlives the tab by a few seconds.
        let deadline = Date.now.addingTimeInterval(15)
        while kill(pid, 0) == 0 {
            guard Date.now < deadline else {
                throw CommandError(
                    errorDescription: "Closed its tab, but process \(pid) is still running.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The terminal `pid` runs on, spelled like iTerm2's `tty` property (`/dev/ttys012`).
    static func tty(of pid: Int32) throws -> String {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            throw CommandError(errorDescription: "Process \(pid) isn't running.")
        }
        // NODEV: no controlling terminal. devname() says "??" for devices it can't name.
        guard info.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR),
            String(cString: name) != "??"
        else {
            throw CommandError(errorDescription: "Process \(pid) isn't attached to a terminal.")
        }
        return "/dev/" + String(cString: name)
    }

    private static func runOnSession(pid: Int32, action: String) async throws {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        let result = try await run(osascript, ["-e", sessionScript, try tty(of: pid), action])
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "found" else {
            throw CommandError(
                errorDescription: "This session is running, but not in an iTerm2 tab (process \(pid)).")
        }
    }

    static func resume(_ session: Session, in directory: String) async throws {
        try await newTab(in: directory, typing: session.profile.resumeCommand(sessionID: session.id))
    }

    /// Opens a tab, `cd`s to `directory` and runs `command` in its shell.
    static func newTab(in directory: String, typing command: String) async throws {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        // argv keeps paths with quotes or spaces out of the script source.
        _ = try await run(osascript, ["-e", newTabScript, directory, command])
    }
}

/// Runs a process off the main thread and returns its stdout.
func run(
    _ executable: URL, _ args: [String], okExitCodes: Set<Int32> = [0],
    environment: [String: String]? = nil
) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            if let environment {
                process.environment = environment
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            // Drain stderr concurrently so a chatty process can't block on a full pipe.
            var errorData = Data()
            let errorReader = DispatchWorkItem {
                errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            }
            DispatchQueue.global().async(execute: errorReader)
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            errorReader.wait()
            guard okExitCodes.contains(process.terminationStatus) else {
                let message = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(
                    throwing: CommandError(
                        errorDescription:
                            "\(executable.lastPathComponent) exited \(process.terminationStatus): \(message)"
                    ))
                return
            }
            continuation.resume(returning: String(decoding: outData, as: UTF8.self))
        }
    }
}
