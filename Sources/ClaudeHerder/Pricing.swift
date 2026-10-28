import Foundation

/// Anthropic API list prices (USD per million tokens), as of 2026-10.
enum Pricing {
    struct Rates {
        let input: Double
        let output: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
        let cacheRead: Double
    }

    static func rates(for model: String) -> Rates? {
        switch model {
        case "claude-fable-5-1":
            return Rates(input: 10, output: 50, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25)
        case "claude-opus-5-5":
            return Rates(input: 4, output: 20, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20)
        case "claude-opus-5":
            return Rates(input: 5, output: 25, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50)
        case "claude-sonnet-5-5":
            return Rates(input: 2, output: 10, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20)
        case "claude-sonnet-4-6":
            return Rates(input: 3, output: 15, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30)
        case "claude-haiku-5-5":
            return Rates(input: 0.10, output: 0.50, cacheWrite5m: 0.125, cacheWrite1h: 0.20, cacheRead: 0.01)
        default:
            return nil
        }
    }

    static func cost(of usage: Usage, rates: Rates) -> Double {
        // Older transcripts lack the 5m/1h split; their writes were all 5m.
        let write1h = usage.cacheCreation?.ephemeral1h ?? 0
        let write5m = usage.cacheCreation?.ephemeral5m ?? (usage.cacheCreationInputTokens ?? 0)
        let microDollars = Double(usage.inputTokens ?? 0) * rates.input
            + Double(usage.outputTokens ?? 0) * rates.output
            + Double(write5m) * rates.cacheWrite5m
            + Double(write1h) * rates.cacheWrite1h
            + Double(usage.cacheReadInputTokens ?? 0) * rates.cacheRead
        return microDollars / 1_000_000
    }
}

/// The `usage` block of an assistant message.
struct Usage: Decodable {
    struct CacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }

    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreation: CacheCreation?

    var totalTokens: Int {
        (inputTokens ?? 0) + (outputTokens ?? 0) + (cacheCreationInputTokens ?? 0)
            + (cacheReadInputTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
    }
}
