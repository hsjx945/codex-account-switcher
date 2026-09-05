import Foundation
import Testing
@testable import CodexAccountSwitcher

struct APITokenValuationTests {
    @Test func separatesCacheFromInputAndDoesNotChargeReasoningTwice() {
        let item = LocalModelTokenUsage(model: "gpt-6-astra", usage: LocalTokenComponents(total: 4_000_000, uncachedInput: 1_000_000, cachedInput: 2_000_000, output: 1_000_000))
        #expect(APITokenValuation.estimate(item) == 62)
        let sol = LocalModelTokenUsage(model: "gpt-5.6-sol", usage: item.usage)
        #expect(APITokenValuation.estimate(sol) == Decimal(string: "24.8"))
    }

    @Test func unknownAndIncompleteUsageNeverBecomeZeroDollarEstimates() {
        let usage = LocalTokenComponents(total: 100, uncachedInput: 50, cachedInput: 40, output: 10)
        let unknown = LocalModelTokenUsage(model: "local-model", usage: usage)
        let incomplete = LocalModelTokenUsage(model: "gpt-6-astra", usage: LocalTokenComponents(total: 100, uncachedInput: nil, cachedInput: nil, output: nil))
        #expect(APITokenValuation.estimate(unknown) == nil)
        #expect(APITokenValuation.estimate(incomplete) == nil)
        #expect(APITokenValuation.subtotal([unknown, incomplete]) == nil)
        let known = LocalModelTokenUsage(model: "gpt-6-astra", usage: usage)
        #expect(APITokenValuation.subtotal([unknown, known]) == APITokenValuation.estimate(known))
        #expect(APITokenValuation.dollars(APITokenValuation.estimate(known)) == "< US$0.01")
    }

    @Test func validatesComponentsAndUsesDecimalRates() {
        let invalid = LocalModelTokenUsage(model: "gpt-6-astra", usage: LocalTokenComponents(total: 100, uncachedInput: 100, cachedInput: 50, output: 10))
        #expect(APITokenValuation.estimate(invalid) == nil)
        let luna = LocalModelTokenUsage(model: "gpt-5.6-luna", usage: LocalTokenComponents(total: 3_000_000, uncachedInput: 1_000_000, cachedInput: 1_000_000, output: 1_000_000))
        #expect(APITokenValuation.estimate(luna) == Decimal(string: "1.42"))
    }
}
