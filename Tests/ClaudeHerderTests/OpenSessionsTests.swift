import XCTest

@testable import ClaudeHerder

final class OpenSessionsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func register(_ name: String, pid: Int32, startedAt: Date, kind: String = "interactive") throws {
        let json = #"{"pid":\#(pid),"sessionId":"\#(name)","startedAt":\#(startedAt.timeIntervalSince1970 * 1000),"kind":"\#(kind)"}"#
        try json.write(to: dir.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8)
    }

    private func processStart(_ pid: Int32) -> Date {
        var info = proc_bsdinfo()
        _ = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec))
    }

    func testOnlyLiveInteractiveSessionsCount() throws {
        let me = getpid()
        try register("live", pid: me, startedAt: processStart(me))
        // Same PID but a different start: the original process died and the PID was reused.
        try register("reused", pid: me, startedAt: processStart(me).addingTimeInterval(-3600))
        try register("background", pid: getppid(), startedAt: processStart(getppid()), kind: "sdk")
        try register("dead", pid: 999_999, startedAt: .now)
        try "secret".write(to: dir.appendingPathComponent("1.abc.key"), atomically: true, encoding: .utf8)

        let result = OpenSessions.scan(dir)

        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.pids, ["live": me])
    }
}

final class OpenSessionsRealTests: XCTestCase {
    /// The session running these tests is open in a terminal, so the real registry must list it.
    func testFindsThisSession() throws {
        let sessionID = try XCTUnwrap(ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"])

        let result = OpenSessions.scan()

        XCTAssertEqual(result.failures, [])
        XCTAssertNotNil(result.pids[sessionID])
    }
}
