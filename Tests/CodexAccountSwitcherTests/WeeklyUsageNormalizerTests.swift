import Foundation
import Testing
@testable import CodexAccountSwitcher

struct WeeklyUsageNormalizerTests {
    @Test func handlesExtremeServerPercentagesWithoutIntegerOverflow() throws {
        for (used, expected) in [(Double.greatestFiniteMagnitude, 0), (-Double.greatestFiniteMagnitude, 100)] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil),
            ])
            #expect(result.remainingPercent == expected)
        }
        for used in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: CodexClientError.malformedResponse) {
                try WeeklyUsageNormalizer.normalize([
                    RateLimitWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil),
                ])
            }
        }
    }

    @Test func selectsLongestWeeklyWindowAndCalculatesRemaining() throws {
        let reset = Date(timeIntervalSince1970: 1_750_000_000)
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 1, windowDurationMins: 300, resetsAt: 10),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 7 * 24 * 60, resetsAt: reset.timeIntervalSince1970),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 6 * 24 * 60, resetsAt: 20),
        ])
        #expect(result.remainingPercent == 42)
        #expect(result.weeklyUsedPercent == 58)
        #expect(result.resetsAt == reset)
        #expect(result.fiveHourRemainingPercent == 99)
        #expect(result.fiveHourResetsAt == Date(timeIntervalSince1970: 10))
    }

    @Test func acceptsSixThroughEightDayWindows() throws {
        for days in [6, 7, 8] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: 25, windowDurationMins: days * 24 * 60, resetsAt: 50),
            ])
            #expect(result.remainingPercent == 75, "days: \(days)")
        }
    }

    @Test func rejectsShortWindows() {
        #expect(throws: CodexClientError.weeklyUsageUnavailable) {
            try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: 25, windowDurationMins: 5 * 60, resetsAt: 50),
                RateLimitWindow(usedPercent: 25, windowDurationMins: 24 * 60, resetsAt: 50),
            ])
        }
    }

    @Test func weeklyUsageStillWorksWhenFiveHourWindowIsMissing() throws {
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 25, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
        ])

        #expect(result.remainingPercent == 75)
        #expect(result.fiveHourRemainingPercent == nil)
        #expect(result.fiveHourResetsAt == nil)
    }

    @Test func acceptsOnlyExactFiveHourWindow() throws {
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 10, windowDurationMins: 4 * 60, resetsAt: 30),
            RateLimitWindow(usedPercent: 35, windowDurationMins: 5 * 60, resetsAt: 40),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 6 * 60, resetsAt: 45),
            RateLimitWindow(usedPercent: 25, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
        ])

        #expect(result.fiveHourRemainingPercent == 65)
        #expect(result.fiveHourResetsAt == Date(timeIntervalSince1970: 40))
    }

    @Test func doesNotLabelFourOrSixHourWindowsAsFiveHour() throws {
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 10, windowDurationMins: 4 * 60, resetsAt: 30),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 6 * 60, resetsAt: 45),
            RateLimitWindow(usedPercent: 25, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
        ])

        #expect(result.fiveHourRemainingPercent == nil)
        #expect(result.fiveHourResetsAt == nil)
    }

    @Test func clampsRemainingPercent() throws {
        for (usedPercent, expected) in [(-5.0, 100), (125.0, 0)] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: usedPercent, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
            ])
            #expect(result.remainingPercent == expected, "used percent: \(usedPercent)")
        }
    }

    @Test func clampsFiveHourRemainingPercent() throws {
        for (usedPercent, expected) in [(-5.0, 100), (125.0, 0)] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: usedPercent, windowDurationMins: 300, resetsAt: 40),
                RateLimitWindow(usedPercent: 20, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
            ])
            #expect(result.fiveHourRemainingPercent == expected, "used percent: \(usedPercent)")
        }
    }

    @Test func preservesUsageWhenResetTimestampsAreMissing() throws {
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 25, windowDurationMins: 300, resetsAt: nil),
            RateLimitWindow(usedPercent: 40, windowDurationMins: 7 * 24 * 60, resetsAt: nil),
        ])

        #expect(result.remainingPercent == 60)
        #expect(result.resetsAt == nil)
        #expect(result.fiveHourRemainingPercent == 75)
        #expect(result.fiveHourResetsAt == nil)
        #expect(!result.allowsWarmup(at: Date()))
    }

    @Test func selectsLatestDateInRealTokenIntersection() {
        let first = TokenActivity(
            dailyBuckets: [
                DailyTokenUsage(startDate: "2026-09-03", tokens: 10),
                DailyTokenUsage(startDate: "2026-09-05", tokens: 20),
            ],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )
        let second = TokenActivity(
            dailyBuckets: [
                DailyTokenUsage(startDate: "2026-09-03", tokens: 30),
                DailyTokenUsage(startDate: "2026-09-04", tokens: 40),
            ],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )

        #expect(TokenActivity.latestCommonDateKey(in: [first, second]) == "2026-09-03")
    }
}
