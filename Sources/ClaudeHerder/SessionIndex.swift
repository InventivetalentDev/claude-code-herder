import Foundation
import Observation

struct IndexFailure: Identifiable, Hashable {
    let path: String
    let message: String

    var id: String { path }
}

/// Scans each Claude profile's `projects` folder for transcripts, reparsing only files that
/// changed since last run, then adds each Codex profile's threads.
enum SessionIndexer {
    struct Result {
        let sessions: [Session]
        let failures: [IndexFailure]
        /// Codex subagent thread ID to its parent; see `CodexIndex.rootThread`.
        let codexParents: [String: String]
    }

    /// A top-level transcript plus the subagent transcripts it spawned.
    private struct Transcript {
        let url: URL
        let subagents: [URL]
        let fingerprint: String
        let profile: Profile
    }

    private struct CacheEntry: Codable {
        let fingerprint: String
        let session: Session?
    }

    private static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeHerder/index-v6.json")

    static func index(profiles: [Profile]) async -> Result {
        let claude = indexClaude(profiles: profiles.filter(\.isClaude))
        var sessions = claude.sessions
        var failures = claude.failures
        var parents: [String: String] = [:]
        for profile in profiles where profile.tool == .codex {
            let codex = await CodexIndex.index(profile: profile)
            sessions += codex.sessions
            failures += codex.failures
            parents.merge(codex.parents) { a, _ in a }
        }
        return Result(sessions: sessions, failures: failures, codexParents: parents)
    }

    static func indexClaude(profiles: [Profile]) -> (
        sessions: [Session], failures: [IndexFailure]
    ) {
        var transcripts: [Transcript] = []
        var rootFailures: [IndexFailure] = []
        for profile in profiles {
            for root in profile.transcriptRoots {
                do {
                    transcripts += try listTranscripts(root: root, profile: profile)
                } catch {
                    rootFailures.append(IndexFailure(path: root.path, message: "\(error)"))
                }
            }
        }

        let cache = loadCache()
        var entries = [CacheEntry?](repeating: nil, count: transcripts.count)
        var failures = [IndexFailure?](repeating: nil, count: transcripts.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: transcripts.count) { i in
            let transcript = transcripts[i]
            if let cached = cache[transcript.url.path], cached.fingerprint == transcript.fingerprint {
                // The profile's label, command or color may have changed in the config since.
                var session = cached.session
                session?.profile = transcript.profile
                let entry = CacheEntry(fingerprint: cached.fingerprint, session: session)
                lock.withLock { entries[i] = entry }
                return
            }
            do {
                let session = try SessionParser.parse(
                    transcript: transcript.url, subagents: transcript.subagents,
                    profile: transcript.profile)
                let entry = CacheEntry(fingerprint: transcript.fingerprint, session: session)
                lock.withLock { entries[i] = entry }
            } catch {
                let failure = IndexFailure(
                    path: transcript.url.path, message: error.localizedDescription)
                lock.withLock { failures[i] = failure }
            }
        }

        var newCache: [String: CacheEntry] = [:]
        for (transcript, entry) in zip(transcripts, entries) {
            newCache[transcript.url.path] = entry
        }
        var allFailures = rootFailures + failures.compactMap { $0 }
        do {
            try saveCache(newCache)
        } catch {
            allFailures.append(IndexFailure(path: cacheURL.path, message: "\(error)"))
        }
        return (deduplicated(entries.compactMap { $0?.session }), allFailures)
    }

    /// Resuming a session in another folder copies its transcript there under the same ID.
    /// Keep one card per ID: the copy with the latest activity.
    static func deduplicated(_ sessions: [Session]) -> [Session] {
        var byID: [String: Session] = [:]
        for session in sessions {
            if let existing = byID[session.id], existing.lastAt >= session.lastAt {
                continue
            }
            byID[session.id] = session
        }
        return Array(byID.values)
    }

    /// Layout: `<root>/<project>/<uuid>.jsonl`, subagents in `<root>/<project>/<uuid>/subagents/`.
    private static func listTranscripts(root: URL, profile: Profile) throws -> [Transcript] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        var transcripts: [Transcript] = []
        let projects = try fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
        for project in projects {
            let files = try fm.contentsOfDirectory(at: project, includingPropertiesForKeys: keys)
            for file in files where file.pathExtension == "jsonl" {
                let subagentDir = file.deletingPathExtension().appendingPathComponent("subagents")
                let subagentFiles = fm.fileExists(atPath: subagentDir.path)
                    ? try fm.contentsOfDirectory(at: subagentDir, includingPropertiesForKeys: keys)
                    : []
                let subagents = subagentFiles
                    .filter { $0.pathExtension == "jsonl" }
                    .sorted { $0.path < $1.path }
                let fingerprint = try ([file] + subagents).map(fingerprintPart).joined(separator: ";")
                transcripts.append(
                    Transcript(url: file, subagents: subagents, fingerprint: fingerprint, profile: profile))
            }
        }
        return transcripts
    }

    private static func fingerprintPart(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent):\(values.fileSize ?? 0):\(mtime)"
    }

    private static func loadCache() -> [String: CacheEntry] {
        // A missing or outdated cache just means a full reparse.
        guard let data = try? Data(contentsOf: cacheURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    private static func saveCache(_ cache: [String: CacheEntry]) throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var failures: [IndexFailure] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Not cached: folders get deleted without touching the transcript.
    private(set) var folderStates: [String: FolderState] = [:]
    private(set) var codexParents: [String: String] = [:]
    /// From the config file, or discovered; reread on every reload.
    private(set) var profiles: [Profile] = []
    private(set) var done = DoneMarks.load()
    /// Sessions running in a terminal right now.
    /// Session ID to the PID of its Claude process.
    private(set) var openPIDs: [String: Int32] = [:]
    private var openFailures: [IndexFailure] = []
    private var indexFailures: [IndexFailure] = []

    func reload() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        let (config, result, states) = await Task.detached(priority: .userInitiated) {
            let config = ProfileConfig.load()
            let result = await SessionIndexer.index(profiles: config.profiles)
            let states = result.sessions.map { ($0.id, FolderState.of(cwd: $0.cwd)) }
            return (config, result, Dictionary(states, uniquingKeysWith: { a, _ in a }))
        }.value
        profiles = config.profiles
        sessions = result.sessions
        codexParents = result.codexParents
        indexFailures = config.failures + result.failures
        failures = indexFailures + openFailures
        folderStates = states
        isLoading = false
        hasLoaded = true
    }

    /// Cheap (a handful of tiny files), so it runs on a short timer.
    func refreshOpenSessions() async {
        let registries = profiles.compactMap(\.registry)
        let result = await Task.detached { OpenSessions.scan(registries) }.value
        openPIDs = result.pids
        openFailures = result.failures
        failures = indexFailures + openFailures
    }

    func toggleDone(_ session: Session) {
        done.toggle(session)
        done.save()
    }

    /// Folders with sessions that still exist, most recently used first.
    func recentFolders(limit: Int = 12) -> [URL] {
        var latest: [String: Date] = [:]
        for session in sessions where folderStates[session.id] == .present {
            guard let cwd = session.cwd else {
                continue
            }
            latest[cwd] = max(latest[cwd] ?? session.lastAt, session.lastAt)
        }
        return latest.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { URL(fileURLWithPath: $0.key) }
    }
}
