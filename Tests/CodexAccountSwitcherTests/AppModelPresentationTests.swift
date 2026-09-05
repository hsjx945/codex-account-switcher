import AppKit
import SwiftUI
import Foundation
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct AppModelPresentationTests {
    @Test func unavailableIdentityRetainsSelectedAccountQuota() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "quota-identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "active"))
        let profile = AccountProfile(id: UUID(), displayName: "Fixture", email: "fixture@example.com", accountID: "fixture", createdAt: Date())
        let home = try await store.createProfileDirectory(id: profile.id)
        try Data("fixture-only".utf8).write(to: home.appending(path: "auth.json"))
        try await store.addProfile(profile)
        try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 91, resetsAt: nil), profileID: profile.id)
        let model = AppModel(store: store, codex: CodexClient(locator: CodexExecutableLocator(explicitURL: URL(fileURLWithPath: "/usr/bin/false"))), switchService: PresentationNoopSwitch(), operationGate: AccountOperationGate())
        await model.start()
        #expect(model.activeIdentityState == .unavailable)
        #expect(model.activeRemainingPercent == 91)
        #expect(model.menuBarQuota.title == "— / 91%")
    }

    @Test func publishesInjectedLocalTokensWithNoSavedAccountsAndStopsMonitoring() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-local-token-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let log = "{\"timestamp\":\"\(timestamp)\",\"type\":\"token_usage_record\",\"payload\":{\"response_id\":\"fixture-response\",\"usage\":{\"total_tokens\":123}}}\n"
        try Data(log.utf8).write(to: sessions.appending(path: "fixture.jsonl"))
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "active"))
        let scanner = LocalSessionUsageScanner(codexHome: root)
        let model = AppModel(store: store, codex: CodexClient(), switchService: PresentationNoopSwitch(), operationGate: AccountOperationGate(), localUsageScanner: scanner)
        await model.start()
        for _ in 0..<50 where model.reportedTokenTotal != 123 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.accounts.isEmpty)
        #expect(model.reportedTokenTotal == 123)
        #expect(await scanner.isMonitoring())
        await model.stopLocalTokenMonitoring()
        #expect(!(await scanner.isMonitoring()))
    }

    @Test func accountPopoverKeepsRowsVisibleDuringCompactSizing() async throws {
        for count in [2, 5] {
            let root = FileManager.default.temporaryDirectory.appending(path: "popover-size-check-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "active"))
            for index in 0..<count {
                let profile = AccountProfile(id: UUID(), displayName: "Fixture \(index)", email: "fixture\(index)@example.com", accountID: "fixture-\(index)", createdAt: Date())
                let home = try await store.createProfileDirectory(id: profile.id)
                try Data("fixture-only".utf8).write(to: home.appending(path: "auth.json"))
                try await store.addProfile(profile)
                try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 50, resetsAt: nil), profileID: profile.id)
            }
            let model = AppModel(store: store, codex: CodexClient(locator: CodexExecutableLocator(explicitURL: URL(fileURLWithPath: "/usr/bin/false"))), switchService: PresentationNoopSwitch(), operationGate: AccountOperationGate())
            await model.start()
            let hosting = NSHostingView(rootView: MenuBarPopover(model: model))
            hosting.setFrameSize(NSSize(width: 420, height: 1))
            hosting.layoutSubtreeIfNeeded()
            let fitted = hosting.fittingSize
            #expect(fitted.width == 420)
            #expect(fitted.height > (count == 2 ? 250 : 560), "Account viewport collapsed for \(count) accounts: \(fitted)")
            // The menu host can propose a compact height before opening.
            // An unconstrained fitting-size check alone misses this regression.
            let renderer = ImageRenderer(content: MenuBarPopover(model: model))
            renderer.proposedSize = ProposedViewSize(width: 420, height: 100)
            let rendered = try #require(renderer.cgImage)
            #expect(rendered.height > (count == 2 ? 250 : 560), "Compact menu proposal collapsed the account viewport")

        }
    }

    @Test func postCommitCleanupWarningRefreshesActiveAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "committed-ui-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "active"))
        var ids: [UUID] = []
        for name in ["first", "second"] {
            let profile = AccountProfile(id: UUID(), displayName: name, email: "\(name)@example.com", accountID: name, createdAt: Date())
            let home = try await store.createProfileDirectory(id: profile.id)
            try Data("fixture-only".utf8).write(to: home.appending(path: "auth.json"))
            try await store.addProfile(profile)
            ids.append(profile.id)
        }
        let model = AppModel(store: store, codex: CodexClient(locator: CodexExecutableLocator(explicitURL: URL(fileURLWithPath: "/usr/bin/false"))), switchService: PresentationCommittedWarning(store: store), operationGate: AccountOperationGate())
        await model.start()
        #expect(model.activeAccountID == ids[0])
        await model.switchAccount(to: ids[1])
        #expect(model.activeAccountID == ids[1])
        #expect(model.activeIdentityState == .unavailable)
        #expect(model.menuBarQuota.title == "—")
        #expect(model.visibleError?.message == "fixture cleanup warning")
        #expect(!model.isMutating)
    }

    @Test func failedSettingsWriteDoesNotEnableWarmupOrChangeVisibleSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "settings-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(baseURL: root, activeHomeURL: root.appending(path: "active"))
        try await store.saveSettings(.default)
        let settingsURL = root.appending(path: "settings.json")
        try FileManager.default.removeItem(at: settingsURL)
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: false)
        let model = AppModel(store: store, codex: CodexClient(), switchService: PresentationNoopSwitch(), operationGate: AccountOperationGate())
        await model.setAutomaticWarmupEnabled(true)
        #expect(!model.settings.automaticWarmupEnabled)
        #expect(model.visibleError != nil)
        #expect(!model.isSavingSettings)
        #expect(await model.updateNickname(id: UUID(), nickname: "Unsaved") == false)
    }

    @Test func tokenReadFailurePreservesLastSuccessfulReadTime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "token-state-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "active"))
        let profile = AccountProfile(id: UUID(), displayName: "Fixture", email: "fixture@example.com", accountID: "fixture", createdAt: Date())
        let home = try await store.createProfileDirectory(id: profile.id)
        try Data("fixture-only".utf8).write(to: home.appending(path: "auth.json"))
        try await store.addProfile(profile)
        try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 50, resetsAt: nil), profileID: profile.id)
        let activity = TokenActivity(dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 123)], modelBreakdown: [], localModelCoverageStartedAt: nil)
        let successfulReadAt = Date(timeIntervalSince1970: 1_700_001_000)
        try await store.cacheTokenActivity(
            activity,
            profileID: profile.id,
            fetchedAt: successfulReadAt
        )
        let executable = root.appending(path: "fixture-codex")
        func writeFixture(tokenResult: String) throws {
            let script = """
            #!/bin/sh
            while IFS= read -r line; do
              case "$line" in
                *initialized*) ;;
                *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
                *rateLimits*) printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":10080}}}}' ;;
                *usage*read*) printf '%s\\n' '\(tokenResult)' ;;
                *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"accountId":"fixture","email":"fixture@example.com"}}}' ;;
              esac
            done
            """
            try Data(script.utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        try writeFixture(tokenResult: "{\"id\":1,\"error\":{\"code\":-1,\"message\":\"fixture offline\"}}")
        let model = AppModel(store: store, codex: CodexClient(locator: CodexExecutableLocator(explicitURL: executable), requestTimeout: .seconds(5)), switchService: PresentationNoopSwitch(), operationGate: AccountOperationGate())
        await model.start()
        #expect(!model.tokenActivityRefreshFinished)
        #expect(model.tokenActivities[profile.id] == activity)
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.tokenActivityRefreshFinished)
        #expect(model.tokenActivities[profile.id] == activity)
        #expect(model.tokenRefreshErrors[profile.id] != nil)
        #expect(model.tokenFetchedAt[profile.id] == successfulReadAt)
        #expect(model.activeRemainingPercent == 75)
        try writeFixture(tokenResult: "{\"id\":1,\"result\":{\"dailyUsageBuckets\":[{\"startDate\":\"2026-09-04\",\"tokens\":456}]}}")
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.tokenRefreshErrors[profile.id] == nil)
        #expect(model.tokenFetchedAt[profile.id] != successfulReadAt)
        #expect(model.reportedTokenTotal == nil)

        let persisted = try await store.loadUsageCache()
        #expect(persisted.entries.first?.tokenFetchedAt != successfulReadAt)
    }

    @Test func tokenCoverageUsesOnlyCurrentBeijingDayWithoutHistoricalFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "token-coverage-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            baseURL: root.appending(path: "store"),
            activeHomeURL: root.appending(path: "active")
        )
        let today = TokenActivity.dateKey()
        let first = AccountProfile(
            id: UUID(), displayName: "First", email: "first@example.com", accountID: "first", createdAt: Date()
        )
        let second = AccountProfile(
            id: UUID(), displayName: "Second", email: "second@example.com", accountID: "second", createdAt: Date()
        )
        for profile in [first, second] {
            let home = try await store.createProfileDirectory(id: profile.id)
            try Data("fixture-only".utf8).write(to: home.appending(path: "auth.json"))
            try await store.addProfile(profile)
            try await store.cacheWeeklyUsage(
                WeeklyUsage(remainingPercent: 50, resetsAt: nil),
                profileID: profile.id
            )
        }
        try await store.cacheTokenActivity(
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: today, tokens: 0)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
            profileID: first.id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.cacheTokenActivity(
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 557_900_000)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
            profileID: second.id,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let model = AppModel(
            store: store,
            codex: CodexClient(locator: CodexExecutableLocator(explicitURL: URL(fileURLWithPath: "/usr/bin/false"))),
            switchService: PresentationNoopSwitch(),
            operationGate: AccountOperationGate()
        )
        await model.start()

        #expect(model.tokenReportingDate == today)
        #expect(model.tokenActivities[first.id]?.tokens(on: today) == 0)
        #expect(model.tokenActivities[second.id]?.tokens(on: today) == nil)
        #expect(model.reportedTokenCoverage.0 == 1)
        #expect(model.reportedTokenCoverage.1 == 2)
        // Daily aggregate data is never presented as a real-time total.
        #expect(model.reportedTokenTotal == nil)
    }
}

private struct PresentationNoopSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws {}
    func recoverIfNeeded() async throws {}
}

private struct PresentationCommittedWarning: SwitchServicing {
    let store: AccountStore
    func recoverIfNeeded() async throws {}
    func switchAccount(to targetID: UUID) async throws {
        try await store.commitActiveAccountID(targetID)
        throw OperationError(stage: nil, titleKey: "operation_failed", messageKey: nil, message: "fixture cleanup warning", underlyingDescription: nil)
    }
}
