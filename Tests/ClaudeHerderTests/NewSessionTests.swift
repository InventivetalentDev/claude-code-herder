import XCTest

@testable import ClaudeHerder

final class NewSessionTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Default commands, as the config gives them when an entry sets no `command`.
    private func profiles(home: URL) throws -> [Profile] {
        try ProfileConfig.profiles(
            from: [
                .init(label: "Personal", dir: "~/.claude"),
                .init(label: "Work", dir: "~/my 'claude'"),
                .init(label: "Codex", dir: "~/.codex", tool: .codex),
                .init(label: "Codex 2", dir: "/opt/codex", tool: .codex),
            ], home: home)
    }

    func testResumeCommands() throws {
        let commands = try profiles(home: URL(fileURLWithPath: "/Users/me"))
            .map { $0.resumeCommand(sessionID: "abc") }

        XCTAssertEqual(commands, [
            "claude --resume abc",
            #"CLAUDE_CONFIG_DIR='/Users/me/my '\''claude'\''' claude --resume abc"#,
            "codex resume abc",
            "CODEX_HOME='/opt/codex' codex resume abc",
        ])
    }

    /// Runs the typed line in a real zsh with `claude` and `codex` stubbed out, as iTerm2
    /// would, and records what each received.
    private func runTypedLine(for profile: Profile, prompt: String) throws -> String {
        let promptFile = dir.appendingPathComponent("prompt.txt")
        try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
        let received = dir.appendingPathComponent("received.txt")
        let out = NewSession.shellQuoted(received.path)
        let stubs = """
            claude() { print -rn -- "config=$CLAUDE_CONFIG_DIR claude:$1" > \(out) }
            codex() { print -rn -- "codex:$1" > \(out) }
            """
        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-f", "-c", "\(stubs)\nunset CLAUDE_CONFIG_DIR\n\(NewSession.command(for: profile, promptFile: promptFile))"]
        try zsh.run()
        zsh.waitUntilExit()

        XCTAssertEqual(zsh.terminationStatus, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: promptFile.path), "prompt file left behind")
        return try String(contentsOf: received, encoding: .utf8)
    }

    func testPromptReachesEachToolIntact() throws {
        let prompt = "Fix the \"quote\" bug, it's $HOME and `ls`\nsecond line"
        let profiles = try profiles(home: URL(fileURLWithPath: "/Users/me"))

        XCTAssertEqual(try runTypedLine(for: profiles[0], prompt: prompt), "config= claude:\(prompt)")
        XCTAssertEqual(
            try runTypedLine(for: profiles[1], prompt: prompt), "config=/Users/me/my 'claude' claude:\(prompt)")
        XCTAssertEqual(try runTypedLine(for: profiles[2], prompt: prompt), "codex:\(prompt)")
    }
}
