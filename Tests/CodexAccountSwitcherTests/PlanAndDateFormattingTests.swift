import Foundation
import Testing
@testable import CodexAccountSwitcher

struct PlanAndDateFormattingTests {
    @Test func showsBadgesOnlyForKnownPlusAndProPlans() {
        let arguments = [
            (planType: "plus", badge: "PLUS"),
            (planType: "pro", badge: "PRO 20X"),
            (planType: "prolite", badge: "PRO 5X"),
            (planType: "future_plan", badge: nil),
            (planType: nil, badge: nil),
        ]

        for argument in arguments {
            let profile = AccountProfile(
                id: UUID(),
                displayName: "Test",
                email: "test@example.com",
                accountID: "acct-test",
                planType: argument.planType,
                createdAt: Date(timeIntervalSince1970: 1),
                lastUsedAt: nil
            )
            #expect(profile.subscriptionBadge == argument.badge, "plan type: \(String(describing: argument.planType))")
        }
    }

    @Test func formatsDatesInChineseUsingBeijingTime() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-09-04T16:26:00Z")
        )

        #expect(BeijingDateTimeFormatter.string(from: date) == "9月5日 00:26")
    }
}
