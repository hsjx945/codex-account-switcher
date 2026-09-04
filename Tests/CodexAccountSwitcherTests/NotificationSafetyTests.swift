import Foundation
import Testing
@testable import CodexAccountSwitcher

struct NotificationSafetyTests {
    @Test func notificationSwitchPolicyOnlyAllowsIdleDirectSwitch() {
        let target = UUID()
        let active = UUID()
        #expect(NotificationSwitchPolicy.disposition(
            targetID: target, activeID: active, isMutating: false, taskState: .idle
        ) == .direct)
        #expect(NotificationSwitchPolicy.disposition(
            targetID: target, activeID: active, isMutating: false, taskState: .active(count: 2)
        ) == .confirmActive(count: 2))
        #expect(NotificationSwitchPolicy.disposition(
            targetID: target, activeID: active, isMutating: false, taskState: .unknown
        ) == .confirmUnknown)
        #expect(NotificationSwitchPolicy.disposition(
            targetID: target, activeID: active, isMutating: true, taskState: .idle
        ) == .operationInProgress)
        #expect(NotificationSwitchPolicy.disposition(
            targetID: active, activeID: active, isMutating: false, taskState: .unknown
        ) == .noAction)
    }

    @Test func independentlyObservedIdleNeverProvesRunningDesktopIsIdle() {
        #expect(DesktopTaskSafetyPolicy.effectiveState(
            desktopIsRunning: true,
            independentlyObservedState: .idle
        ) == .unknown)
        #expect(DesktopTaskSafetyPolicy.effectiveState(
            desktopIsRunning: true,
            independentlyObservedState: .active(count: 2)
        ) == .active(count: 2))
        #expect(DesktopTaskSafetyPolicy.effectiveState(
            desktopIsRunning: false,
            independentlyObservedState: nil
        ) == .idle)
    }

    @Test func fiveHourResetReminderIsDeduplicatedByServerResetTimestamp() {
        let resetAt = Date(timeIntervalSince1970: 1_000)
        let usage = WeeklyUsage(
            remainingPercent: 50,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            fiveHourRemainingPercent: 100,
            fiveHourResetsAt: resetAt
        )
        let refreshedUsage = WeeklyUsage(
            remainingPercent: 50,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            fiveHourRemainingPercent: 100,
            fiveHourResetsAt: Date(timeIntervalSince1970: 2_800)
        )
        #expect(FiveHourResetDetector.resetToNotify(
            previousUsage: usage, currentUsage: refreshedUsage,
            lastNotifiedResetAt: nil, now: Date(timeIntervalSince1970: 1_001)
        ) == resetAt)
        #expect(FiveHourResetDetector.resetToNotify(
            previousUsage: usage, currentUsage: refreshedUsage,
            lastNotifiedResetAt: resetAt, now: Date(timeIntervalSince1970: 1_001)
        ) == nil)
        #expect(FiveHourResetDetector.resetToNotify(
            previousUsage: usage, currentUsage: refreshedUsage,
            lastNotifiedResetAt: nil, now: Date(timeIntervalSince1970: 999)
        ) == nil)
        #expect(FiveHourResetDetector.resetToNotify(
            previousUsage: usage, currentUsage: usage,
            lastNotifiedResetAt: nil, now: Date(timeIntervalSince1970: 1_001)
        ) == nil)
    }
}
