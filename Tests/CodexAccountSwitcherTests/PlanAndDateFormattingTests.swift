import Foundation
import Testing
@testable import CodexAccountSwitcher

struct PlanAndDateFormattingTests {
    @Test func showsBadgesOnlyForKnownSubscriptionPlans() {
        let arguments = [
            (planType: "free", badge: "Free"),
            (planType: "plus", badge: "Plus"),
            (planType: "team", badge: "Team"),
            (planType: "pro", badge: "Pro 20x"),
            (planType: "prolite", badge: "Pro 5x"),
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

    @Test func preferredLabelUsesNicknameThenEmailThenDisplayName() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1)
        let nickname = AccountProfile(
            id: id,
            displayName: "Display",
            nickname: "Work",
            email: "work@example.com",
            accountID: nil,
            createdAt: createdAt
        )
        let email = AccountProfile(
            id: id,
            displayName: "Display",
            nickname: "  ",
            email: "work@example.com",
            accountID: nil,
            createdAt: createdAt
        )
        let displayName = AccountProfile(
            id: id,
            displayName: "Display",
            email: nil,
            accountID: nil,
            createdAt: createdAt
        )

        #expect(nickname.preferredLabel == "Work")
        #expect(email.preferredLabel == "work@example.com")
        #expect(displayName.preferredLabel == "Display")
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
        #expect(activity.latestDateKey == "2026-09-03")
        #expect(activity.tokens(on: "2026-09-03") == 100)
        #expect(activity.tokens(on: "2026-09-04") == nil)

        let zeroToday = TokenActivity(
            dailyBuckets: [
                DailyTokenUsage(startDate: "2026-09-03", tokens: 557_900_000),
                DailyTokenUsage(startDate: "2026-09-04", tokens: 0),
            ],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )
        #expect(zeroToday.tokensForToday(now: now, calendar: calendar) == 0)
        #expect(zeroToday.tokens(on: "2026-09-04") == 0)
    }

    @Test func recomputesBeijingNaturalDayAtMidnightBoundary() throws {
        let beforeMidnight = try #require(
            ISO8601DateFormatter().date(from: "2026-09-04T15:59:59Z")
        )
        let atMidnight = try #require(
            ISO8601DateFormatter().date(from: "2026-09-04T16:00:00Z")
        )
        #expect(TokenActivity.dateKey(for: beforeMidnight) == "2026-09-04")
        #expect(TokenActivity.dateKey(for: atMidnight) == "2026-09-05")

        let activity = TokenActivity(
            dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 557)],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )
        #expect(activity.tokensForToday(now: beforeMidnight) == 557)
        #expect(activity.tokensForToday(now: atMidnight) == nil)
    }

    @Test func formatsDatesInChineseUsingBeijingTime() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-09-04T16:26:00Z")
        )

        #expect(BeijingDateTimeFormatter.string(from: date) == "9月5日 00:26")
    }

    @Test func quotaRowsUseExplicitTextLabels() {
        #expect(L10n.string("five_hour", language: .english) == "5-hour")
        #expect(L10n.string("weekly", language: .english) == "Weekly")
        #expect(L10n.string("five_hour", language: .simplifiedChinese) == "5 小时")
        #expect(L10n.string("weekly", language: .simplifiedChinese) == "周额度")
    }
}
