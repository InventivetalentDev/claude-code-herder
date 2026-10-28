import Foundation
import Observation

struct IndexFailure: Identifiable, Hashable {
    let path: String
    let message: String

    var id: String { path }
}

/// Scans `~/.claude/projects` for transcripts, reparsing only files that changed since last run.
enum SessionIndexer {
    struct Result {
        let sessions: [Session]
        let failures: [IndexFailure]
    }

    /// A top-level transcript plus the subagent transcripts it spawned.
    private struct Transcript {
        let url: URL
        let subagents: [URL]
        let fingerprint: String
    }

    private struct CacheEntry: Codable {
        let fingerprint: String
        let session: Session?
    }

    static let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    private static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeHerder/index-v1.json")

    static func index(root: URL = projectsRoot) -> Result {
        let transcripts: [Transcript]
        do {
            transcripts = try listTranscripts(root: root)
        } catch {
            return Result(sessions: [], failures: [IndexFailure(path: root.path, message: "\(error)")])
        }

        let cache = loadCache()
        var entries = [CacheEntry?](repeating: nil, count: transcripts.count)
        var failures = [IndexFailure?](repeating: nil, count: transcripts.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: transcripts.count) { i in
            let transcript = transcripts[i]
            if let cached = cache[transcript.url.path], cached.fingerprint == transcript.fingerprint {
                lock.withLock { entries[i] = cached }
                return
            }
            do {
                let session = try SessionParser.parse(
                    transcript: transcript.url, subagents: transcript.subagents)
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
        var allFailures = failures.compactMap { $0 }
        do {
            try saveCache(newCache)
        } catch {
            allFailures.append(IndexFailure(path: cacheURL.path, message: "\(error)"))
        }
        return Result(sessions: entries.compactMap { $0?.session }, failures: allFailures)
    }

    /// Layout: `<root>/<project>/<uuid>.jsonl`, subagents in `<root>/<project>/<uuid>/subagents/`.
    private static func listTranscripts(root: URL) throws -> [Transcript] {
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
                transcripts.append(Transcript(url: file, subagents: subagents, fingerprint: fingerprint))
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

    func reload() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { SessionIndexer.index() }.value
        sessions = result.sessions
        failures = result.failures
        isLoading = false
        hasLoaded = true
    }
}
