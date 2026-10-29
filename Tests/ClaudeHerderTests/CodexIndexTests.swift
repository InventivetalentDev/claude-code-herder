import XCTest

@testable import ClaudeHerder

final class CodexIndexTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Just the columns we read, as Codex's schema has them.
    private func makeDatabase(_ name: String, _ sql: String) throws {
        let schema = """
            create table threads (id text primary key, cwd text not null, title text not null,
                name text, first_user_message text not null default '', created_at integer not null,
                updated_at integer not null, created_at_ms integer, updated_at_ms integer,
                tokens_used integer not null default 0, thread_source text);
            create table thread_spawn_edges (parent_thread_id text not null,
                child_thread_id text not null primary key, status text not null);
            """
        let sqlite = Process()
        sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = [home.appendingPathComponent(name).path, schema + sql]
        try sqlite.run()
        sqlite.waitUntilExit()
        XCTAssertEqual(sqlite.terminationStatus, 0)
    }

    func testReadsUserThreadsFromNewestDatabase() async throws {
        try makeDatabase("state_2.sqlite", "insert into threads values ('old', '/x', 't', null, 'p', 0, 0, null, null, 0, 'user');")
        try makeDatabase("state_10.sqlite", """
            insert into threads values
                ('named', '/work/a', 'Fix it', 'Fix the bug', 'Fix it please', 100, 200, 100500, 200500, 1234, 'user'),
                ('unnamed', '/work/b', 'Do the thing', '', 'Do the thing', 100, 200, null, null, 5, 'user'),
                ('never-prompted', '/work/c', '', null, '', 100, 200, null, null, 0, 'user'),
                ('sub', '/work/a', 'Sub', null, 'Sub task', 100, 200, null, null, 9, 'subagent');
            insert into thread_spawn_edges values ('named', 'sub', 'done'), ('sub', 'subsub', 'done');
            """)

        let result = await CodexIndex.index(profile: .test(.codex, home: home.path))

        XCTAssertEqual(result.failures, [])
        let sessions = Dictionary(uniqueKeysWithValues: result.sessions.map { ($0.id, $0) })
        XCTAssertEqual(Set(sessions.keys), ["named", "unnamed"])
        let named = try XCTUnwrap(sessions["named"])
        XCTAssertEqual(named.profile, .test(.codex, home: home.path))
        XCTAssertEqual(named.title, "Fix the bug")
        XCTAssertEqual(named.firstPrompt, "Fix it please")
        XCTAssertEqual(named.cwd, "/work/a")
        XCTAssertEqual(named.firstAt, Date(timeIntervalSince1970: 100.5))
        XCTAssertEqual(named.lastAt, Date(timeIntervalSince1970: 200.5))
        XCTAssertEqual(named.tokens, 1234)
        XCTAssertNil(named.messageCount)
        XCTAssertNil(named.costUSD)
        // An empty name falls back to the title; missing _ms columns to the seconds ones.
        XCTAssertEqual(sessions["unnamed"]?.title, "Do the thing")
        XCTAssertEqual(sessions["unnamed"]?.lastAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(CodexIndex.rootThread(of: "subsub", parents: result.parents), "named")
    }

    func testMissingDatabaseIsAFailure() async {
        let result = await CodexIndex.index(profile: .test(.codex, home: home.path))

        XCTAssertEqual(result.sessions, [])
        XCTAssertEqual(result.failures.count, 1)
    }

    func testRootThreadSurvivesCycles() {
        XCTAssertEqual(CodexIndex.rootThread(of: "a", parents: [:]), "a")
        let root = CodexIndex.rootThread(of: "a", parents: ["a": "b", "b": "a"])
        XCTAssertTrue(["a", "b"].contains(root))
    }

    func testMapsTranscriptPathsToSessions() {
        let parents = ["0190aaaa-0000-7000-8000-00000000000b": "0190aaaa-0000-7000-8000-00000000000a"]
        func id(_ path: String) -> String {
            TranscriptSearch.sessionID(forTranscript: URL(fileURLWithPath: path), codexParents: parents)
        }

        XCTAssertEqual(
            id("/c/sessions/2025/01/02/rollout-2025-01-02T10-00-00-0190aaaa-0000-7000-8000-00000000000c.jsonl"),
            "0190aaaa-0000-7000-8000-00000000000c")
        XCTAssertEqual(
            id("/c/sessions/2025/01/02/rollout-2025-01-02T11-00-00-0190aaaa-0000-7000-8000-00000000000b.jsonl.zst"),
            "0190aaaa-0000-7000-8000-00000000000a")
        XCTAssertEqual(id("/p/-Users-me-proj/abc.jsonl"), "abc")
        XCTAssertEqual(id("/p/-Users-me-proj/abc/subagents/agent-1.jsonl"), "abc")
    }
}
