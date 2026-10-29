import XCTest

@testable import ClaudeHerder

final class SessionParserTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ lines: [String], trailingNewline: Bool = true) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let usage = #"{"input_tokens":1000000,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}"#

    func testSummarizesTranscript() throws {
        let transcript = try write("abc.jsonl", [
            #"{"type":"user","isMeta":true,"timestamp":"2026-10-01T09:00:00.000Z","message":{"role":"user","content":"Caveat"}}"#,
            #"{"type":"user","cwd":"/work/proj","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user","content":"Fix the bug"}}"#,
            // Two streamed blocks of one reply: counted once, usage once.
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:05.000Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"text","text":"On it"}],"usage":\#(usage)}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:06.000Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"usage":\#(usage)}}"#,
            #"{"type":"user","timestamp":"2026-10-01T10:00:07.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            // Tool-only reply: not a message, but billed.
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:08.000Z","message":{"id":"m2","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{}}],"usage":\#(usage)}}"#,
            // Claude cd'd into a subfolder; resuming still needs the starting folder.
            #"{"type":"user","cwd":"/work/proj/sub","timestamp":"2026-10-01T11:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"Thanks"}]}}"#,
            #"{"type":"system","subtype":"away_summary","content":"Fixed the bug. (disable recaps in /config)","timestamp":"2026-10-01T11:30:00.000Z"}"#,
            #"{"type":"ai-title","aiTitle":"Bug fixing"}"#,
            #"{"type":"custom-title","customTitle":"my-bug"}"#,
            #"{"type":"file-history-snapshot","snapshot":{}}"#,
        ])
        let subagent = try write("agent.jsonl", [
            #"{"type":"assistant","timestamp":"2026-10-01T10:30:00.000Z","message":{"id":"s1","model":"claude-haiku-5-5","content":[],"usage":\#(usage)}}"#,
        ])

        let session = try XCTUnwrap(
            SessionParser.parse(transcript: transcript, subagents: [subagent], profile: .test(home: "/w")))

        XCTAssertEqual(session.id, "abc")
        XCTAssertEqual(session.profile, .test(home: "/w"))
        XCTAssertEqual(session.cwd, "/work/proj")
        XCTAssertEqual(session.title, "my-bug")
        XCTAssertEqual(session.recap, "Fixed the bug.")
        XCTAssertEqual(session.firstPrompt, "Fix the bug")
        XCTAssertEqual(session.messageCount, 3)
        XCTAssertEqual(session.firstAt, try Date("2026-10-01T10:00:00Z", strategy: .iso8601))
        XCTAssertEqual(session.lastAt, try Date("2026-10-01T11:00:00Z", strategy: .iso8601))
        // Two Opus replies at $4/MTok input + one Haiku subagent reply at $0.10.
        XCTAssertEqual(try XCTUnwrap(session.costUSD), 8.10, accuracy: 1e-9)
    }

    func testSlashCommandsReadAsTyped() throws {
        let transcript = try write("cmd.jsonl", [
            #"{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user","content":"<command-name>/login</command-name>\n<command-message>login</command-message>\n<command-args></command-args>"}}"#,
            #"{"type":"user","timestamp":"2026-10-01T10:00:01.000Z","message":{"role":"user","content":"<local-command-stdout>Login successful</local-command-stdout>"}}"#,
            #"{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","message":{"role":"user","content":"<command-message>impeccable</command-message> <command-name>/impeccable</command-name> <command-args>critique the page</command-args>"}}"#,
        ])

        let session = try XCTUnwrap(
            SessionParser.parse(transcript: transcript, subagents: [], profile: .test()))

        XCTAssertEqual(session.firstPrompt, "/impeccable critique the page")
        XCTAssertEqual(session.messageCount, 3)
    }

    func testIgnoresLineStillBeingWritten() throws {
        let transcript = try write("live.jsonl", [
            #"{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user","content":"Hi"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:01.000Z","message":{"id":"m1","con"#,
        ], trailingNewline: false)

        let session = try XCTUnwrap(
            SessionParser.parse(transcript: transcript, subagents: [], profile: .test()))

        XCTAssertEqual(session.messageCount, 1)
    }

    func testUnknownModelMakesCostUnknown() throws {
        let transcript = try write("x.jsonl", [
            #"{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"role":"user","content":"Hi"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T10:00:01.000Z","message":{"id":"m1","model":"claude-future-9","content":[],"usage":\#(usage)}}"#,
        ])

        XCTAssertNil(try SessionParser.parse(transcript: transcript, subagents: [], profile: .test())?.costUSD)
    }

    func testCorruptLineFails() throws {
        let transcript = try write("bad.jsonl", [#"{"type":"user", nope}"#])

        XCTAssertThrowsError(try SessionParser.parse(transcript: transcript, subagents: [], profile: .test()))
    }

    func testEmptyTranscriptHasNoSession() throws {
        let transcript = try write("empty.jsonl", [#"{"type":"file-history-snapshot"}"#])

        XCTAssertNil(try SessionParser.parse(transcript: transcript, subagents: [], profile: .test()))
    }

    private var realProfiles: [Profile] {
        get throws {
            let config = ProfileConfig.load()
            XCTAssertEqual(config.failures, [])
            try XCTSkipIf(config.profiles.isEmpty, "no Claude or Codex folders here")
            return config.profiles
        }
    }

    /// Smoke test over the real profiles: everything must index.
    func testIndexesRealTranscripts() async throws {
        let profiles = try realProfiles
        let start = Date()
        let result = await SessionIndexer.index(profiles: profiles)
        print("indexed \(result.sessions.count) sessions in \(Date().timeIntervalSince(start))s")
        for profile in profiles {
            let sessions = result.sessions.filter { $0.profile == profile }
            print(profile.label, sessions.count, "sessions,", sessions.filter { $0.costUSD == nil }.count, "without cost")
            for s in sessions.sorted(by: { $0.lastAt > $1.lastAt }).prefix(3) {
                print(" ", s.id, s.projectName, s.title, s.messageCount ?? -1, s.costUSD ?? -1, s.tokens ?? -1)
            }
        }
        XCTAssertEqual(result.failures, [])
        // Duplicate IDs leave holes in the SwiftUI grid.
        XCTAssertEqual(Set(result.sessions.map(\.id)).count, result.sessions.count)
        for profile in profiles {
            XCTAssertTrue(result.sessions.contains { $0.profile == profile }, profile.label)
        }
    }

    /// Every word must match somewhere in the session; this session's own ID is a known hit.
    func testSearchesRealTranscripts() async throws {
        let sessionID = try XCTUnwrap(ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"])
        let roots = try realProfiles.flatMap(\.transcriptRoots)

        let hits = try await TranscriptSearch.sessionIDs(matching: "herder ITERM2", in: roots)
        // A fresh UUID can't be in any transcript, even this session's.
        let misses = try await TranscriptSearch.sessionIDs(
            matching: "herder \(UUID().uuidString)", in: roots)

        XCTAssertTrue(hits.contains(sessionID))
        XCTAssertEqual(misses, [])
    }

    /// Older Codex rollouts are zstd-compressed; each one names its own thread ID inside.
    func testSearchesCompressedCodexRollouts() async throws {
        let profile = try XCTUnwrap(try realProfiles.first { $0.tool == .codex })
        let codex = await CodexIndex.index(profile: profile)
        let ids = Set(codex.sessions.map(\.id))
        let compressed = try XCTUnwrap(
            FileManager.default.enumerator(at: profile.transcriptRoots[0], includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.pathExtension == "zst" && ids.contains(String($0.lastPathComponent.dropLast(".jsonl.zst".count).suffix(36))) })
        let id = TranscriptSearch.sessionID(forTranscript: compressed, codexParents: codex.parents)

        let hits = try await TranscriptSearch.sessionIDs(
            matching: id, in: profile.transcriptRoots, codexParents: codex.parents)

        XCTAssertTrue(hits.contains(id), "\(compressed.path) not found")
    }
}
