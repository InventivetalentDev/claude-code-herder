import Foundation

/// One Claude Code or Codex session.
struct Session: Codable, Identifiable, Hashable {
    /// The session UUID, as accepted by `claude --resume` / `codex resume`.
    let id: String
    /// Settable so cached sessions pick up edits to the profile config.
    var profile: Profile
    /// Folder the session started in; `claude --resume` only finds the session from there.
    let cwd: String?
    let title: String
    /// Latest recap Claude wrote when the user stepped away; nil if it never did.
    let recap: String?
    let firstPrompt: String?
    let firstAt: Date
    let lastAt: Date
    /// User prompts plus assistant replies that contain text (tool-only turns don't count).
    /// Nil for Codex, whose thread index doesn't count messages.
    let messageCount: Int?
    /// API list price in USD, subagents included; nil when a model has no known price.
    let costUSD: Double?
    /// Codex's running token total; nil for Claude, whose cost says more.
    var tokens: Int? = nil

    var projectName: String {
        guard let cwd else {
            return "Unknown folder"
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
