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

    private var cache: URL {
        home.appendingPathComponent("usage-cache.json")
    }

    /// Just the columns we read, as Codex's schema has them.
    private func makeDatabase(_ name: String, _ sql: String) throws {
        let schema = """
            create table threads (id text primary key, cwd text not null, title text not null,
                name text, first_user_message text not null default '', created_at integer not null,
                updated_at integer not null, created_at_ms integer, updated_at_ms integer,
                tokens_used integer not null default 0, thread_source text, model text);
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
        try makeDatabase("state_2.sqlite", "insert into threads values ('old', '/x', 't', null, 'p', 0, 0, null, null, 0, 'user', null);")
        try makeDatabase("state_10.sqlite", """
            insert into threads values
                ('named', '/work/a', 'Fix it', 'Fix the bug', 'Fix it please', 100, 200, 100500, 200500, 1234, 'user', null),
                ('unnamed', '/work/b', 'Do the thing', '', 'Do the thing', 100, 200, null, null, 5, 'user', null),
                ('never-prompted', '/work/c', '', null, '', 100, 200, null, null, 0, 'user', null),
                ('sub', '/work/a', 'Sub', null, 'Sub task', 100, 200, null, null, 9, 'subagent', null);
            insert into thread_spawn_edges values ('named', 'sub', 'done'), ('sub', 'subsub', 'done');
            """)

        let result = await CodexIndex.index(profile: .test(.codex, home: home.path), usageCache: cache)

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
        // No rollouts, so no requests to pay for.
        XCTAssertEqual(named.costUSD, 0)
        // An empty name falls back to the title; missing _ms columns to the seconds ones.
        XCTAssertEqual(sessions["unnamed"]?.title, "Do the thing")
        XCTAssertEqual(sessions["unnamed"]?.lastAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(CodexIndex.rootThread(of: "subsub", parents: result.parents), "named")
    }

    private static let threads = (0..<5).map { "0190aaaa-0000-7000-8000-00000000000\($0)" }

    /// A rollout with one `token_usage_record` line per (input, cached, output) request.
    @discardableResult
    private func writeRollout(
        _ thread: String, requests: [(Int, Int, Int)], extraLines: [String] = []
    ) throws -> URL {
        let dir = home.appendingPathComponent("sessions/2025/01/02")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let records = requests.map { input, cached, output in
            #"{"timestamp":"2025-01-02T10:00:00.000Z","type":"token_usage_record","payload":{"thread_id":"\#(thread)","#
                + #""usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":0,"#
                + #""output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}}}"#
        }
        let url = dir.appendingPathComponent("rollout-2025-01-02T10-00-00-\(thread).jsonl")
        try ((records + extraLines).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testCostsIncludeSubagentsAndLongContextRates() async throws {
        let t = Self.threads
        try makeDatabase("state_5.sqlite", """
            insert into threads values
                ('\(t[0])', '/w', 'A', null, 'Do A', 0, 0, null, null, 0, 'user', 'gpt-6.1-sol'),
                ('\(t[1])', '/w', 'B', null, 'Sub of A', 0, 0, null, null, 0, 'subagent', 'gpt-6-astra'),
                ('\(t[2])', '/w', 'C', null, 'Do C', 0, 0, null, null, 0, 'user', 'some-local-model'),
                ('\(t[3])', '/w', 'D', null, 'Review', 0, 0, null, null, 0, 'guardian_review', 'codex-auto-review'),
                ('\(t[4])', '/w', 'E', null, 'Do E', 0, 0, null, null, 0, 'user', 'gpt-6-sol');
            insert into thread_spawn_edges values ('\(t[0])', '\(t[1])', 'done');
            """)
        // Compaction quotes earlier records in its history; counting those would bill twice.
        let compacted = #"{"type":"compacted","payload":{"replacement_history":[{"type":"token_usage_record","#
            + #""payload":{"usage":{"input_tokens":5000,"cached_input_tokens":0,"output_tokens":5000}}}]}}"#
        try writeRollout(
            t[0], requests: [(100_000, 90_000, 1_000), (300_000, 280_000, 2_000)], extraLines: [compacted])
        try writeRollout(t[1], requests: [(10_000, 0, 1_000)])
        try writeRollout(t[2], requests: [(1_000, 0, 100)])
        try writeRollout(t[3], requests: [(1_000, 0, 100)])

        let result = await CodexIndex.index(profile: .test(.codex, home: home.path), usageCache: cache)

        XCTAssertEqual(result.failures, [])
        let sessions = Dictionary(uniqueKeysWithValues: result.sessions.map { ($0.id, $0) })
        XCTAssertEqual(Set(sessions.keys), [t[0], t[2], t[4]])
        // A at gpt-6.1-sol: 10K fresh, 90K cached, 1K out at short-context rates ($0.039), then
        // 20K fresh, 280K cached, 2K out at long-context ones ($0.166). Its subagent B at
        // gpt-6-astra: 10K fresh, 1K out ($0.15).
        XCTAssertEqual(try XCTUnwrap(sessions[t[0]]?.costUSD), 0.355, accuracy: 1e-9)
        XCTAssertNil(try XCTUnwrap(sessions[t[2]]).costUSD, "model without a price")
        XCTAssertEqual(sessions[t[4]]?.costUSD, 0, "never made a request")
    }

    func testUsageIsRescannedOnlyWhenARolloutChanges() async throws {
        let thread = Self.threads[0]
        let roots = [home.appendingPathComponent("sessions")]
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try writeRollout(thread, requests: [(1_000, 0, 100)])
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: url.path)
        let first = try await CodexUsage.byThread(roots: roots, cacheURL: cache)

        // Same size and date: the cached sums stand.
        try writeRollout(thread, requests: [(2_000, 0, 200)])
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: url.path)
        let cached = try await CodexUsage.byThread(roots: roots, cacheURL: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: then.addingTimeInterval(1)], ofItemAtPath: url.path)
        let rescanned = try await CodexUsage.byThread(roots: roots, cacheURL: cache)

        XCTAssertEqual(first[thread]?.short, CodexUsage.Tokens(input: 1_000, cachedInput: 0, output: 100))
        XCTAssertEqual(cached, first)
        XCTAssertEqual(rescanned[thread]?.short, CodexUsage.Tokens(input: 2_000, cachedInput: 0, output: 200))
    }

    func testMissingDatabaseIsAFailure() async {
        let result = await CodexIndex.index(profile: .test(.codex, home: home.path), usageCache: cache)

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
