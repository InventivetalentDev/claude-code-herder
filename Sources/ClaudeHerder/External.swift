import Foundation

struct CommandError: LocalizedError {
    let errorDescription: String?
}

/// Full-text search over transcripts by shelling out to ripgrep.
enum TranscriptSearch {
    /// Session IDs whose transcript (or subagent transcripts) contain every word of `query`.
    static func sessionIDs(matching query: String, in root: URL) async throws -> Set<String> {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let rg = try ripgrepURL()
        return try await withThrowingTaskGroup(of: Set<String>.self) { group in
            for word in words {
                group.addTask { try await filesMatching(word: word, rg: rg, root: root) }
            }
            var matches: Set<String>?
            for try await ids in group {
                matches = matches?.intersection(ids) ?? ids
            }
            return matches ?? []
        }
    }

    private static func filesMatching(word: String, rg: URL, root: URL) async throws -> Set<String> {
        let args = [
            "--files-with-matches", "--fixed-strings", "--ignore-case", "--no-ignore",
            "--glob", "*.jsonl", "--", word, root.path,
        ]
        let output = try await run(rg, args, okExitCodes: [0, 1])  // 1 = no matches
        let paths = output.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        return Set(paths.map(sessionID(forTranscript:)))
    }

    /// Subagent transcripts live in `<uuid>/subagents/`; they belong to session `<uuid>`.
    private static func sessionID(forTranscript url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" {
            return parent.deletingLastPathComponent().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func ripgrepURL() throws -> URL {
        // GUI apps don't inherit the shell PATH, so look in the usual install spots.
        let candidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw CommandError(errorDescription: "ripgrep not found; install it with `brew install ripgrep`")
        }
        return URL(fileURLWithPath: path)
    }
}

/// Opens and finds Claude sessions in Ghostty tabs, via Ghostty's AppleScript dictionary.
enum Ghostty {
    private static let script = """
        on run argv
            set dir to item 1 of argv
            set cmd to item 2 of argv
            tell application "Ghostty"
                activate
                set cfg to new surface configuration
                set initial working directory of cfg to dir
                set initial input of cfg to cmd & return
                if (count of windows) is 0 then
                    new window with configuration cfg
                else
                    new tab in front window with configuration cfg
                end if
            end tell
        end run
        """

    private static let focusScript = """
        on run argv
            set target to (item 1 of argv) as integer
            tell application "Ghostty"
                repeat with t in terminals
                    if (pid of t) is target then
                        focus t
                        activate
                        return "focused"
                    end if
                end repeat
            end tell
            return "missing"
        end run
        """

    /// Brings forward the tab whose foreground process is `pid` (a running Claude session).
    static func focus(pid: Int32) async throws {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        let result = try await run(osascript, ["-e", focusScript, String(pid)])
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "focused" else {
            throw CommandError(
                errorDescription: "This session is running, but not in a Ghostty tab (process \(pid)).")
        }
    }

    static func resume(sessionID: String, in directory: String) async throws {
        try await newTab(in: directory, typing: "claude --resume \(sessionID)")
    }

    /// Opens a tab in `directory` and types `command` into its shell, then Return.
    static func newTab(in directory: String, typing command: String) async throws {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        // argv keeps paths with quotes or spaces out of the script source.
        _ = try await run(osascript, ["-e", script, directory, command])
    }
}

/// Runs a process off the main thread and returns its stdout.
func run(_ executable: URL, _ args: [String], okExitCodes: Set<Int32> = [0]) async throws
    -> String
{
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = args
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
