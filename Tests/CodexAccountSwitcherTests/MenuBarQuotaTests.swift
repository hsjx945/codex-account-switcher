import Foundation
import Testing
@testable import CodexAccountSwitcher

struct MenuBarQuotaTests {
    @Test func rejectsOverflowingOrNegativeTokenTotals() {
        #expect(TokenActivity.checkedTokenTotal([Int.max, 1]) == nil)
        #expect(TokenActivity.checkedTokenTotal([-1, 2]) == nil)
        #expect(TokenActivity.checkedTokenTotal([0, 12]) == 12)
        let activity = TokenActivity(dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: Int.max), DailyTokenUsage(startDate: "2026-09-04", tokens: 1)], modelBreakdown: [], localModelCoverageStartedAt: nil)
        #expect(activity.tokens(on: "2026-09-04") == nil)
    }

    @Test func blankIdentityNeverAuthenticatesBlankStoredProfile() {
        let profile = AccountProfile(id: UUID(), displayName: "Fixture", email: " ", accountID: "", createdAt: Date())
        #expect(!AccountIdentity(accountID: "", email: " ").matches(profile))
    }

    @Test func displaysWeeklyQuotaIndependentOfFiveHourQuota() {
        let usage = WeeklyUsage(remainingPercent: 50, resetsAt: nil, fiveHourRemainingPercent: 100)
        #expect(MenuBarQuotaPresentation(state: .loaded(usage), identityConfirmed: true).title == "50%")
    }

    @Test func missingOrUnverifiedQuotaIsNeverReportedAsZero() {
        let states: [UsageViewState?] = [nil, .idle, .unavailable("offline")]
        for state in states {
            #expect(MenuBarQuotaPresentation(state: state, identityConfirmed: true).title == "—")
        }
        let usage = WeeklyUsage(remainingPercent: 50, resetsAt: nil)
        #expect(MenuBarQuotaPresentation(state: .loaded(usage), identityConfirmed: false).title == "—")
    }

    @Test func marksStaleQuotaAndPreservesActualZero() {
        let usage = WeeklyUsage(remainingPercent: 0, resetsAt: nil)
        let fresh = MenuBarQuotaPresentation(state: .loaded(usage), identityConfirmed: true)
        #expect(fresh.title == "0%")
        #expect(!fresh.isStale)
        let stale = MenuBarQuotaPresentation(state: .stale(usage, "offline"), identityConfirmed: true)
        #expect(stale.title == "0%!")
        #expect(stale.isStale)
    }

    @Test func clampsOutOfRangeCachedValues() {
        for (input, expected) in [(-3, "0%"), (103, "100%")] {
            let usage = WeeklyUsage(remainingPercent: input, resetsAt: nil)
            #expect(MenuBarQuotaPresentation(state: .loaded(usage), identityConfirmed: true).title == expected)
        }
    }
}
