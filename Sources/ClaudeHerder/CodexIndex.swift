import Foundation

/// Codex sessions, from the `threads` table of Codex's own state database. Reading the
/// rollouts instead would mean decompressing most of them (older ones are `.jsonl.zst`);
/// only costs come from there, through `CodexUsage`, which caches what it reads.
enum CodexIndex {
    struct Result {
        let sessions: [Session]
        /// Subagent thread ID to the thread that spawned it.
        let parents: [String: String]
        let failures: [IndexFailure]
    }

    private struct Row: Decodable {
        let id: String
        let cwd: String
        let title: String
        let name: String?
        let firstUserMessage: String
        let createdAtMs: Int64
        let updatedAtMs: Int64
        let tokensUsed: Int

        enum CodingKeys: String, CodingKey {
            case id, cwd, title, name
            case firstUserMessage = "first_user_message"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case tokensUsed = "tokens_used"
        }
    }

    private struct Edge: Decodable {
        let child: String
        let parent: String
    }

    private struct ThreadModel: Decodable {
        let id: String
        let model: String
    }

    /// What each thread the user started cost, its subagents' threads included. Auto-review
    /// threads have no spawn edge, and their model no list price, so they're left out.
    private struct Costs {
        private var totals: [String: Double] = [:]
        /// Threads with requests on a model that has no known price.
        private var unpriced: Set<String> = []

        init(usage: [String: CodexUsage.Split], models: [String: String], parents: [String: String]) {
            for (thread, split) in usage {
                let root = CodexIndex.rootThread(of: thread, parents: parents)
                // At the model the thread last used; switching models mid-thread is rare.
                if let cost = OpenAIPricing.cost(of: split, model: models[thread]) {
                    totals[root, default: 0] += cost
                } else {
                    unpriced.insert(root)
                }
            }
        }

        func of(_ thread: String) -> Double? {
            unpriced.contains(thread) ? nil : totals[thread, default: 0]
        }
    }

    // `user` covers the TUI, the desktop app and `codex exec`; subagents and auto-review
    // threads have their own thread_source. Threads never prompted have no first message.
    private static let threadsQuery = """
        select id, cwd, title, name, first_user_message,
            coalesce(created_at_ms, created_at * 1000) as created_at_ms,
            coalesce(updated_at_ms, updated_at * 1000) as updated_at_ms,
            tokens_used
        from threads
        where thread_source = 'user' and first_user_message != ''
        """
    private static let edgesQuery =
        "select child_thread_id as child, parent_thread_id as parent from thread_spawn_edges"
    private static let modelsQuery = "select id, model from threads where model is not null"

    static func index(profile: Profile, usageCache: URL = CodexUsage.cacheURL) async -> Result {
        do {
            let db = try database(in: profile.home)
            let rows: [Row] = try await query(db, threadsQuery)
            let edges: [Edge] = try await query(db, edgesQuery)
            let models: [ThreadModel] = try await query(db, modelsQuery)
            let parents = Dictionary(edges.map { ($0.child, $0.parent) }, uniquingKeysWith: { a, _ in a })
            var costs: Costs?
            var failures: [IndexFailure] = []
            do {
                costs = Costs(
                    usage: try await CodexUsage.byThread(roots: profile.transcriptRoots, cacheURL: usageCache),
                    models: Dictionary(models.map { ($0.id, $0.model) }, uniquingKeysWith: { a, _ in a }),
                    parents: parents)
            } catch {
                failures.append(
                    IndexFailure(
                        path: profile.transcriptRoots[0].path,
                        message: "Can't estimate costs: \(error.localizedDescription)"))
            }
            return Result(
                sessions: rows.map { session($0, profile: profile, cost: costs?.of($0.id)) },
                parents: parents,
                failures: failures)
        } catch {
            return Result(
                sessions: [], parents: [:],
                failures: [IndexFailure(path: profile.home.path, message: error.localizedDescription)])
        }
    }

    /// `state_5.sqlite` today; the number goes up when Codex changes its schema.
    static func database(in home: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
        let versions = files.compactMap { url -> (version: Int, url: URL)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                let version = Int(name.dropFirst("state_".count).dropLast(".sqlite".count))
            else {
                return nil
            }
            return (version, url)
        }
        guard let newest = versions.max(by: { $0.version < $1.version }) else {
            throw CommandError(errorDescription: "No state_*.sqlite in \(home.path)")
        }
        return newest.url
    }

    /// The thread ID in a rollout's name, `rollout-<timestamp>-<uuid>.jsonl`, which Codex
    /// compresses to `.jsonl.zst` once old. Nil for other files.
    static func threadID(ofRollout url: URL) -> String? {
        let name = url.lastPathComponent
        for ext in [".jsonl", ".jsonl.zst"] where name.hasPrefix("rollout-") && name.hasSuffix(ext) {
            return String(name.dropLast(ext.count).suffix(36))
        }
        return nil
    }

    /// Follows subagent links up to the thread the user started.
    static func rootThread(of id: String, parents: [String: String]) -> String {
        var id = id
        var seen: Set<String> = []
        while let parent = parents[id], seen.insert(id).inserted {
            id = parent
        }
        return id
    }

    private static func query<T: Decodable>(_ db: URL, _ sql: String) async throws -> [T] {
        let sqlite = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // Not -readonly: the database is in WAL mode, and a read-only connection can't recreate
        // the -wal/-shm files Codex removes whenever it closes it. We only ever SELECT.
        // Codex writes while it runs; wait out its locks instead of failing.
        let output = try await run(sqlite, ["-json", "-cmd", ".timeout 2000", db.path, sql])
        // No rows prints nothing at all, not `[]`.
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return try JSONDecoder().decode([T].self, from: Data(output.utf8))
    }

    private static func session(_ row: Row, profile: Profile, cost: Double?) -> Session {
        let name = row.name.flatMap { $0.isEmpty ? nil : $0 }
        let title = row.title.isEmpty ? nil : row.title
        return Session(
            id: row.id,
            profile: profile,
            cwd: row.cwd.isEmpty ? nil : row.cwd,
            title: name ?? title ?? row.firstUserMessage,
            recap: nil,
            firstPrompt: row.firstUserMessage,
            firstAt: Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000),
            lastAt: Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000),
            messageCount: nil,
            costUSD: cost,
            tokens: row.tokensUsed)
    }
}
