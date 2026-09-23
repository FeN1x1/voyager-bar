import Foundation

/// USD per million tokens (standard tier, first-party API).
struct TokenPrice {
    let input: Double
    let output: Double
    let cacheRead: Double
    /// Cache writes (Anthropic): 1.25× input for the 5-minute TTL, 2× for 1 hour.
    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2 }
}

enum Pricing {
    /// Anthropic list prices (cached 2026-06-24 in Anthropic's model reference).
    static let anthropic: [(prefix: String, price: TokenPrice)] = [
        ("claude-fable-5-1", TokenPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", TokenPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", TokenPrice(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-mythos-5", TokenPrice(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-opus-5-5", TokenPrice(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", TokenPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", TokenPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", TokenPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", TokenPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-5", TokenPrice(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-1", TokenPrice(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-opus-4", TokenPrice(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-sonnet-5", TokenPrice(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", TokenPrice(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-3-7-sonnet", TokenPrice(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-3-5-sonnet", TokenPrice(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-4-5", TokenPrice(input: 1, output: 5, cacheRead: 0.10)),
        ("claude-3-5-haiku", TokenPrice(input: 0.8, output: 4, cacheRead: 0.08)),
    ]

    /// OpenAI list prices (developers.openai.com pricing, September 2026).
    static let openAI: [(prefix: String, price: TokenPrice)] = [
        ("gpt-6-astra", TokenPrice(input: 10, output: 50, cacheRead: 1.0)),
        ("gpt-6-sol", TokenPrice(input: 2, output: 10, cacheRead: 0.20)),
        ("gpt-6-luna", TokenPrice(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("gpt-5.6-sol", TokenPrice(input: 4, output: 20, cacheRead: 0.40)),
        ("gpt-5.6-terra", TokenPrice(input: 2, output: 12, cacheRead: 0.20)),
        ("gpt-5.6-luna", TokenPrice(input: 0.20, output: 1.20, cacheRead: 0.02)),
        ("gpt-5.5-pro", TokenPrice(input: 30, output: 180, cacheRead: 30)),
        ("gpt-5.5", TokenPrice(input: 5, output: 30, cacheRead: 0.50)),
        ("gpt-5.4-mini", TokenPrice(input: 0.75, output: 4.50, cacheRead: 0.075)),
        ("gpt-5.4-nano", TokenPrice(input: 0.20, output: 1.25, cacheRead: 0.02)),
        ("gpt-5.4", TokenPrice(input: 2.50, output: 15, cacheRead: 0.25)),
        ("gpt-5.3-codex", TokenPrice(input: 1.75, output: 14, cacheRead: 0.175)),
        ("gpt-5.2", TokenPrice(input: 1.75, output: 14, cacheRead: 0.175)),
        ("gpt-5.1", TokenPrice(input: 1.25, output: 10, cacheRead: 0.125)),
        ("gpt-5-mini", TokenPrice(input: 0.25, output: 2, cacheRead: 0.025)),
        ("gpt-5-nano", TokenPrice(input: 0.05, output: 0.40, cacheRead: 0.005)),
        ("gpt-5", TokenPrice(input: 1.25, output: 10, cacheRead: 0.125)),
    ]

    /// Longest matching prefix wins ("claude-opus-5-5" before "claude-opus-5").
    static func price(for model: String, in table: [(prefix: String, price: TokenPrice)]) -> TokenPrice? {
        let m = model.lowercased()
        return table.filter { m.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.price
    }
}
