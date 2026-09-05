import Foundation

/// Standard short-context text-token price equivalents, USD per million tokens.
/// Official model pages checked 2026-09-05. This is not a subscription bill.
enum APITokenValuation {
    struct Rate: Sendable {
        let input: Decimal
        let cached: Decimal
        let output: Decimal
    }

    static let verifiedOn = "2026-09-05"
    static let rates: [String: Rate] = [
        "gpt-6-astra": Rate(input: 10, cached: 1, output: 50),
        "gpt-5.6-sol": Rate(input: 4, cached: Decimal(string: "0.4")!, output: 20),
        "gpt-5.6": Rate(input: 4, cached: Decimal(string: "0.4")!, output: 20),
        "gpt-5.6-luna": Rate(input: Decimal(string: "0.2")!, cached: Decimal(string: "0.02")!, output: Decimal(string: "1.2")!),
    ]

    static func estimate(_ item: LocalModelTokenUsage) -> Decimal? {
        guard let model = item.model, let rate = rates[model],
              let input = item.usage.uncachedInput, let cached = item.usage.cachedInput,
              let output = item.usage.output,
              input >= 0, cached >= 0, output >= 0,
              Decimal(input) + Decimal(cached) + Decimal(output) == Decimal(item.usage.total)
        else { return nil }
        return (Decimal(input) * rate.input + Decimal(cached) * rate.cached + Decimal(output) * rate.output) / 1_000_000
    }

    static func subtotal(_ items: [LocalModelTokenUsage]) -> Decimal? {
        let values = items.compactMap(estimate)
        guard !values.isEmpty else { return nil }
        return values.reduce(Decimal.zero, +)
    }

    static func dollars(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        if value > 0 && value < Decimal(string: "0.01")! { return "< US$0.01" }
        return "US$" + String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}
