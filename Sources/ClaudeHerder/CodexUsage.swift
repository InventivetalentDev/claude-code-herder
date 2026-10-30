import Foundation

/// Token usage per Codex thread, from the `token_usage_record` line Codex appends to a thread's
/// rollout after every model request. The database only keeps a running total, which can't
/// tell cached input (a tenth of the price or less) from fresh input.
enum CodexUsage {
    /// Summed over requests. `input` includes `cachedInput`, as in Codex's logs.
    struct Tokens: Codable, Equatable {
        var input = 0
        var cachedInput = 0
        var output = 0

        var isEmpty: Bool {
            input == 0 && output == 0
        }

        mutating func add(_ other: Tokens) {
            input += other.input
            cachedInput += other.cachedInput
            output += other.output
        }
    }

    /// Requests over the long-context threshold are billed at other rates, so they're summed apart.
    struct Split: Codable, Equatable {
        var short = Tokens()
        var long = Tokens()

        var isEmpty: Bool {
            short.isEmpty && long.isEmpty
        }
    }

    private struct CacheEntry: Codable {
        let fingerprint: String
        let usage: Split
    }

    /// One rollout line. Only `token_usage_record` lines carry a `usage`.
    private struct Line: Decodable {
        struct Payload: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int
            let cachedInputTokens: Int
            let outputTokens: Int

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
            }
        }

        let type: String
        let payload: Payload?
    }

    static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeHerder/codex-usage-v1.json")

    /// Thread ID to its usage. A rollout only grows until Codex compresses it, so each is
    /// rescanned only when its size or modification date changes.
    static func byThread(roots: [URL], cacheURL: URL = cacheURL) async throws -> [String: Split] {
        let files = rollouts(in: roots)
        var fingerprints: [String: String] = [:]
        for file in files {
            fingerprints[file.path] = try SessionIndexer.fingerprintPart(file)
        }
        var cache = loadCache(cacheURL)
        let stale = files.filter { cache[$0.path]?.fingerprint != fingerprints[$0.path] }
        let scanned = try await scan(stale)
        for file in stale {
            cache[file.path] = CacheEntry(
                fingerprint: fingerprints[file.path] ?? "", usage: scanned[file.path] ?? Split())
        }
        // Forget rollouts that are gone (compressed ones get a new name), but keep other profiles'.
        let current = Set(files.map(\.path))
        cache = cache.filter { path, _ in
            current.contains(path) || !roots.contains { path.hasPrefix($0.path + "/") }
        }
        // A cache that can't be saved only means rescanning next time.
        try? saveCache(cache, to: cacheURL)

        var usage: [String: Split] = [:]
        for file in files {
            guard let thread = CodexIndex.threadID(ofRollout: file), let split = cache[file.path]?.usage,
                !split.isEmpty
            else {
                continue
            }
            usage[thread] = split
        }
        return usage
    }

    private static func rollouts(in roots: [URL]) -> [URL] {
        roots.flatMap { root in
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            return (files?.allObjects as? [URL] ?? []).filter { CodexIndex.threadID(ofRollout: $0) != nil }
        }
    }

    /// Rollout path to its usage, for rollouts with at least one record.
    private static func scan(_ files: [URL]) async throws -> [String: Split] {
        guard !files.isEmpty else {
            return [:]
        }
        let (rg, environment) = try Tools.ripgrep()
        let decoder = JSONDecoder()
        var usage: [String: Split] = [:]
        // A few hundred paths per run keeps the arguments well under the system's limit.
        for start in stride(from: 0, to: files.count, by: 256) {
            let batch = files[start..<min(start + 256, files.count)]
            let args = [
                "--with-filename", "--null", "--no-line-number", "--fixed-strings", "--search-zip",
                "--", #""type":"token_usage_record""#,
            ] + batch.map(\.path)
            // Any other exit (say, a rollout compressed mid-scan) fails this round, rather than
            // caching that rollout as unused.
            let output = try await run(rg, args, okExitCodes: [0, 1], environment: environment)  // 1 = no matches
            // Each line is `<path>\0<json>`.
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "\0", maxSplits: 1)
                // `compacted` lines quote earlier records inside their history; only count the
                // records themselves.
                guard parts.count == 2,
                    let record = try? decoder.decode(Line.self, from: Data(parts[1].utf8)),
                    record.type == "token_usage_record", let request = record.payload?.usage
                else {
                    continue
                }
                let tokens = Tokens(
                    input: request.inputTokens, cachedInput: request.cachedInputTokens,
                    output: request.outputTokens)
                if tokens.input > OpenAIPricing.longContextThreshold {
                    usage[String(parts[0]), default: Split()].long.add(tokens)
                } else {
                    usage[String(parts[0]), default: Split()].short.add(tokens)
                }
            }
        }
        return usage
    }

    private static func loadCache(_ url: URL) -> [String: CacheEntry] {
        // A missing or outdated cache just means a full rescan.
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    private static func saveCache(_ cache: [String: CacheEntry], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }
}
