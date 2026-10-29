import Foundation

@testable import ClaudeHerder

extension Profile {
    /// A profile for tests that don't care where sessions live.
    static func test(_ tool: Tool = .claude, home: String = "/tmp/herder-test-profile") -> Profile {
        Profile(
            label: tool.rawValue, tool: tool, home: URL(fileURLWithPath: home), command: tool.rawValue,
            color: 0)
    }
}
