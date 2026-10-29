import XCTest

@testable import ClaudeHerder

final class ProfileConfigTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    private func writeConfig(_ json: String) throws -> URL {
        try mkdir(".config/claude-herder")
        let url = home.appendingPathComponent(".config/claude-herder/profiles.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var noConfig: URL {
        home.appendingPathComponent(".config/claude-herder/profiles.json")
    }

    func testDiscoversClaudeAndCodexFolders() throws {
        try mkdir(".claude/projects")
        try mkdir(".claude-work/projects")
        try mkdir(".claude-unused")  // never ran a session: no projects folder
        try "{}".write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        try mkdir(".codex")
        try Data().write(to: home.appendingPathComponent(".codex/state_5.sqlite"))

        let result = ProfileConfig.load(from: noConfig, home: home)

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.profiles.map(\.label), ["Claude", "work", "Codex"])
        XCTAssertEqual(result.profiles.map(\.tool), [.claude, .claude, .codex])
        XCTAssertEqual(
            result.profiles.map(\.command),
            ["claude", "CLAUDE_CONFIG_DIR='\(home.path)/.claude-work' claude", "codex"])
        XCTAssertEqual(result.profiles.map(\.color), [0xD97757, 0x3B6EA8, 0x5E5D59])
    }

    func testConfigFileReplacesDiscovery() throws {
        try mkdir(".claude/projects")
        let url = try writeConfig("""
            {"profiles": [
                {"label": "Work", "dir": "~/.claude-work", "color": "#112233"},
                {"label": "Personal", "dir": "/elsewhere/claude", "command": "claude-personal"},
                {"label": "Codex", "dir": "~/.codex/", "tool": "codex"}
            ]}
            """)

        let result = ProfileConfig.load(from: url, home: home)

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.profiles.map(\.label), ["Work", "Personal", "Codex"])
        XCTAssertEqual(
            result.profiles.map(\.id),
            ["\(home.path)/.claude-work", "/elsewhere/claude", "\(home.path)/.codex"])
        XCTAssertEqual(
            result.profiles.map(\.command),
            ["CLAUDE_CONFIG_DIR='\(home.path)/.claude-work' claude", "claude-personal", "codex"])
        XCTAssertEqual(result.profiles.map(\.color), [0x112233, 0x3B6EA8, 0x5E5D59])
    }

    /// A broken config is reported, and the app keeps working with what it can discover.
    func testBrokenConfigFallsBackToDiscovery() throws {
        try mkdir(".claude/projects")
        let broken = [
            #"{"profiles": [{"label": "A", "dir": "~/a"}"#,
            #"{"profiles": [{"label": "A", "dir": "~/a", "tool": "gemini"}]}"#,
            #"{"profiles": [{"label": "A", "dir": "~/a"}, {"label": "B", "dir": "~/a/"}]}"#,
            #"{"profiles": [{"label": "A", "dir": "~/a", "color": "red"}]}"#,
            #"{"profiles": [{"dir": "~/a"}]}"#,
        ]
        for json in broken {
            let result = ProfileConfig.load(from: try writeConfig(json), home: home)

            XCTAssertEqual(result.failures.count, 1, json)
            XCTAssertEqual(result.profiles.map(\.label), ["Claude"], json)
        }
    }
}
