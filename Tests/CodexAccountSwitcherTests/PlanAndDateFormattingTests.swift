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
            #expect(profile.supportsFiveHourUsage == !["pro", "prolite"].contains(argument.planType))
        }
    }

    @Test func distinguishesMissingTodayBucketFromZeroUsage() throws {
        let activity = TokenActivity(
            dailyBuckets: [DailyTokenUsage(startDate: "2026-09-03", tokens: 100)],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-04T04:00:00Z"))

        #expect(activity.tokensForToday(now: now, calendar: calendar) == nil)
        #expect(activity.tokensIfCovered(inLastDays: 1, now: now, calendar: calendar) == nil)
        #expect(activity.tokensIfCovered(inLastDays: 7, now: now, calendar: calendar) == 100)
    }

    @Test func formatsDatesInChineseUsingBeijingTime() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-09-04T16:26:00Z")
        )

        #expect(BeijingDateTimeFormatter.string(from: date) == "9月5日 00:26")
    }
}
