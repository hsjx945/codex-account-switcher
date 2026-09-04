import CryptoKit
import Darwin
import Foundation
import ServiceManagement

enum CheckFailure: Error {
    case failed(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func requireDate(_ value: String) throws -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        throw CheckFailure.failed("invalid fixture date: \(value)")
    }
    return date
}

private func lineCount(at url: URL) -> Int {
    guard let data = try? Data(contentsOf: url) else { return 0 }
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count
}

private func waitForLineCount(at url: URL, atLeast expected: Int) async throws {
    for _ in 0..<250 {
        if lineCount(at: url) >= expected { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CheckFailure.failed(
        "timed out waiting for \(expected) refresh requests; observed \(lineCount(at: url))"
    )
}

private actor Recorder {
    private var values: [SwitchStage] = []
    func append(_ value: SwitchStage) { values.append(value) }
    func snapshot() -> [SwitchStage] { values }
}

private struct FakeDesktop: DesktopControlling {
    let recorder: Recorder
    func isDesktopRunning() async -> Bool { true }
    func closeDesktop() async throws { await recorder.append(.closeDesktop) }
    func reopenDesktop() async throws { await recorder.append(.reopenDesktop) }
}

private actor FakeStore: AccountStoring {
    let recorder: Recorder
    let original: AccountProfile
    let target: AccountProfile

    init(recorder: Recorder, original: AccountProfile, target: AccountProfile) {
        self.recorder = recorder
        self.original = original
        self.target = target
    }

    func loadRegistry() -> AccountRegistry {
        AccountRegistry(activeAccountID: original.id, accounts: [original, target])
    }
    func profile(id: UUID) -> AccountProfile { target }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func readActiveCredential() -> Data { Data("original".utf8) }
    func createProfileDirectory(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() async { await recorder.append(.saveCurrentCredential) }
    func activateTargetCredential(id: UUID) async { await recorder.append(.activateTargetCredential) }
    func restoreActiveCredential(id: UUID) {}
    func restoreCredential(_ credential: Data) {}
    func commitActiveAccountID(_ id: UUID) async { await recorder.append(.commitActiveAccountID) }
}

private struct FakeCodex: CodexIdentityReading {
    let recorder: Recorder
    let target: AccountProfile

    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        await recorder.append(.verifyTargetIdentity)
        return AccountIdentity(accountID: target.accountID, email: target.email)
    }
}

private struct InjectedReopenFailure: LocalizedError {
    var errorDescription: String? { "Injected Desktop reopen failure" }
}

private struct ReopenFailureSwitchService: SwitchServicing {
    let store: AccountStore

    func switchAccount(to targetID: UUID) async throws {
        try await store.commitActiveAccountID(targetID)
        throw OperationError.stage(.reopenDesktop, InjectedReopenFailure())
    }

    func recoverIfNeeded() async throws {}
}

private struct CoreRollbackKeyProvider: RollbackKeyProviding {
    func loadOrCreateKey() throws -> SymmetricKey {
        SymmetricKey(data: Data(repeating: 0x42, count: 32))
    }
}

private actor CoreRecoveryDesktop: DesktopControlling {
    private var opens = 0
    func isDesktopRunning() -> Bool { true }
    func closeDesktop() async throws {}
    func reopenDesktop() async throws { opens += 1 }
    func reopenCount() -> Int { opens }
}

private actor CoreRecoveryStore: AccountStoring {
    let original: AccountProfile
    let target: AccountProfile
    let originalBytes: Data
    let targetBytes: Data
    private var activeID: UUID
    private var credentialBytes: Data
    private var credentialID: UUID

    init(original: AccountProfile, target: AccountProfile) {
        self.original = original
        self.target = target
        originalBytes = Data("core-original-credential".utf8)
        targetBytes = Data("core-target-credential".utf8)
        activeID = original.id
        credentialBytes = originalBytes
        credentialID = original.id
    }

    func loadRegistry() -> AccountRegistry {
        AccountRegistry(activeAccountID: activeID, accounts: [original, target])
    }
    func profile(id: UUID) throws -> AccountProfile {
        guard id == original.id || id == target.id else { throw AccountStoreError.profileNotFound }
        return id == original.id ? original : target
    }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/\(id.uuidString)") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/core-active") }
    func activeCredentialExists() -> Bool { true }
    func readActiveCredential() -> Data { credentialBytes }
    func createProfileDirectory(id: UUID) -> URL { profileHome(id: id) }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() {}
    func activateTargetCredential(id: UUID) {
        credentialBytes = targetBytes
        credentialID = target.id
    }
    func restoreActiveCredential(id: UUID) {
        credentialBytes = originalBytes
        credentialID = original.id
    }
    func restoreCredential(_ credential: Data) {
        credentialBytes = credential
        credentialID = original.id
    }
    func commitActiveAccountID(_ id: UUID) { activeID = id }
    func simulateInterruptedActivation() {
        credentialBytes = targetBytes
        credentialID = target.id
    }
    func activeAccountID() -> UUID { activeID }
    func activeCredential() -> Data { credentialBytes }
    func credentialOwner() -> UUID { credentialID }
}

private struct CoreRecoveryCodex: CodexIdentityReading {
    let store: CoreRecoveryStore
    let original: AccountProfile
    let target: AccountProfile
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        let owner = await store.credentialOwner()
        let profile = owner == original.id ? original : target
        return AccountIdentity(accountID: profile.accountID, email: profile.email)
    }
}

private actor CoreConcurrencyProbe {
    private var active = 0
    private var maximum = 0
    func enter() {
        active += 1
        maximum = max(maximum, active)
    }
    func leave() { active -= 1 }
    func maximumConcurrency() -> Int { maximum }
}

private actor CoreNotificationService: QuotaNotificationServicing {
    private var authorizationRequests = 0
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return true
    }
    func sendFiveHourResetNotification(
        profileID: UUID,
        accountLabel: String,
        title: String,
        body: String,
        resetAt: Date
    ) async throws {}
    func requestCount() -> Int { authorizationRequests }
}

private func createExecutable(at url: URL, body: String) throws {
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
}

@main
struct CoreChecks {
    @MainActor static func main() async throws {
        try require(
            LaunchAtLoginState(status: .notRegistered) == .disabled,
            "not-registered launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .enabled) == .enabled,
            "enabled launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .requiresApproval) == .requiresApproval,
            "approval-required launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .notFound) == .unavailable,
            "unavailable launch-at-login state"
        )

        let weekly = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 90, windowDurationMins: 300, resetsAt: 1),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 10_080, resetsAt: 1_750_000_000),
        ])
        try require(weekly.remainingPercent == 42, "weekly remaining percent")
        try require(weekly.fiveHourRemainingPercent == 10, "five-hour remaining percent")
        let nonExactFiveHour = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 10, windowDurationMins: 240, resetsAt: 1),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 360, resetsAt: 1),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 10_080, resetsAt: 1_750_000_000),
        ])
        try require(
            nonExactFiveHour.fiveHourRemainingPercent == nil,
            "four-hour and six-hour windows are not five-hour usage"
        )
        try require(
            L10n.string("show_five_hour_usage", language: .english) == "Show 5-hour Usage",
            "English five-hour setting label"
        )
        try require(
            L10n.string("show_five_hour_usage", language: .simplifiedChinese) == "显示 5 小时用量",
            "Simplified Chinese five-hour setting label"
        )
        let plusProfile = AccountProfile(
            id: UUID(), displayName: "Plus", email: "plus@example.com", accountID: "plus",
            planType: "plus", createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil
        )
        let proProfile = AccountProfile(
            id: UUID(), displayName: "Pro", email: "pro@example.com", accountID: "pro",
            planType: "pro", createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil
        )
        let proLiteProfile = AccountProfile(
            id: UUID(), displayName: "Pro Lite", email: "prolite@example.com", accountID: "prolite",
            planType: "prolite", createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil
        )
        let unknownProfile = AccountProfile(
            id: UUID(), displayName: "Unknown", email: "unknown@example.com", accountID: "unknown",
            planType: "future_plan", createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil
        )
        try require(plusProfile.subscriptionBadge == "PLUS", "plus plan identification")
        try require(proProfile.subscriptionBadge == "PRO 20X", "pro plan identification")
        try require(proLiteProfile.subscriptionBadge == "PRO 5X", "pro lite plan identification")
        try require(unknownProfile.subscriptionBadge == nil, "unknown plan does not get a badge")
        try require(plusProfile.supportsFiveHourUsage, "plus may show five-hour usage")
        try require(!proProfile.supportsFiveHourUsage, "pro never shows five-hour usage")
        try require(!proLiteProfile.supportsFiveHourUsage, "pro 5x never shows five-hour usage")
        let missingToday = TokenActivity(
            dailyBuckets: [DailyTokenUsage(startDate: "2026-09-03", tokens: 100)],
            modelBreakdown: [],
            localModelCoverageStartedAt: nil
        )
        var beijingCalendar = Calendar(identifier: .gregorian)
        beijingCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let beijingNow = try requireDate("2026-09-04T04:00:00Z")
        try require(
            missingToday.tokensForToday(
                now: beijingNow,
                calendar: beijingCalendar
            ) == nil,
            "a missing current-day server bucket is not reported as zero usage"
        )
        try require(
            missingToday.tokensIfCovered(
                inLastDays: 1,
                now: beijingNow,
                calendar: beijingCalendar
            ) == nil,
            "an uncovered server period remains unknown"
        )
        let beijingDate = try requireDate("2026-09-04T16:26:00Z")
        try require(
            BeijingDateTimeFormatter.string(from: beijingDate) == "9月5日 00:26",
            "reset dates use Chinese Beijing time"
        )
        let noFiveHourWindow = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 20, windowDurationMins: 299, resetsAt: 1),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 301, resetsAt: 2),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 10_080, resetsAt: 1_750_000_000),
        ])
        try require(
            noFiveHourWindow.fiveHourRemainingPercent == nil && noFiveHourWindow.fiveHourResetsAt == nil,
            "missing exact 300-minute window leaves five-hour usage absent"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "switcher-check-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        let scanHome = root.appending(path: "model-scan", directoryHint: .isDirectory)
        let scanSessions = scanHome.appending(path: "sessions", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: scanSessions, withIntermediateDirectories: true)
        let scanFixture = scanSessions.appending(path: "usage.jsonl")
        try Data("""
        {"timestamp":"2026-09-04T09:00:00Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-09-04T09:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}
        {"timestamp":"2026-09-04T09:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}
        {"timestamp":"2026-09-04T09:03:00Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-09-04T09:04:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160}}}}
        """.utf8).write(to: scanFixture)
        let scanNow = try requireDate("2026-09-04T12:00:00Z")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let modelSummary = await LocalSessionUsageScanner(codexHome: scanHome).scan(
            now: scanNow,
            calendar: utcCalendar
        )
        try require(
            modelSummary.models == [
                LocalModelTokenUsage(
                    model: "gpt-5.6-sol",
                    todayTokens: 100,
                    sevenDayTokens: 100,
                    thirtyDayTokens: 100
                ),
                LocalModelTokenUsage(
                    model: "gpt-5.6-luna",
                    todayTokens: 60,
                    sevenDayTokens: 60,
                    thirtyDayTokens: 60
                ),
            ],
            "local model usage uses cumulative deltas and accepts both ISO timestamp forms"
        )

        let activeHome = root.appending(path: "active")
        let support = root.appending(path: "support")
        try fileManager.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: activeHome.appending(path: "auth.json"))

        let store = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let first = AccountProfile(
            id: UUID(), displayName: "First", email: "first@example.com",
            accountID: "first", createdAt: Date(), lastUsedAt: nil
        )
        try await store.importCurrentProfile(first)
        let firstCredential = await store.profileHome(id: first.id).appending(path: "auth.json")
        let firstPermissions = try permissions(firstCredential)
        try require(firstPermissions == 0o600, "imported credential permissions")

        let second = AccountProfile(
            id: UUID(), displayName: "Second", email: "second@example.com",
            accountID: "second", createdAt: Date(), lastUsedAt: nil
        )
        let secondHome = try await store.createProfileDirectory(id: second.id)
        let secondBytes = Data("second".utf8)
        try secondBytes.write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        let third = AccountProfile(
            id: UUID(), displayName: "Third", email: "third@example.com",
            accountID: "third", createdAt: Date(), lastUsedAt: nil
        )
        let thirdHome = try await store.createProfileDirectory(id: third.id)
        try Data("third".utf8).write(to: thirdHome.appending(path: "auth.json"))
        try await store.addProfile(third)
        try await store.activateTargetCredential(id: second.id)
        let activeCredential = activeHome.appending(path: "auth.json")
        let activeBytes = try Data(contentsOf: activeCredential)
        let activePermissions = try permissions(activeCredential)
        try require(activeBytes == secondBytes, "credential activation")
        try require(activePermissions == 0o600, "active credential permissions")

        let cachedWeekly = WeeklyUsage(
            remainingPercent: 73,
            resetsAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let cachedAt = Date(timeIntervalSince1970: 1_749_000_000)
        try await store.cacheWeeklyUsage(cachedWeekly, profileID: first.id, fetchedAt: cachedAt)
        let persistedCache = try await store.loadUsageCache()
        try require(
            persistedCache.entries == [
                UsageCacheEntry(profileID: first.id, usage: cachedWeekly, fetchedAt: cachedAt),
            ],
            "weekly usage cache persistence"
        )
        let usageCachePermissions = try permissions(support.appending(path: "usage-cache.json"))
        try require(usageCachePermissions == 0o600, "weekly usage cache permissions")
        let notifiedResetAt = Date(timeIntervalSince1970: 1_749_500_000)
        try await store.markFiveHourResetNotified(profileID: first.id, resetAt: notifiedResetAt)
        let cacheAfterNotification = try await store.loadUsageCache()
        try require(
            cacheAfterNotification.entries.first?.lastNotifiedFiveHourResetAt == notifiedResetAt,
            "five-hour reset notification dedupe persistence"
        )

        let legacyCacheData = Data("""
        {"entries":[{"profileID":"\(first.id.uuidString)","usage":{"remainingPercent":73,"resetsAt":"2025-06-15T15:06:40Z"},"fetchedAt":"2025-06-04T01:20:00Z"}]}
        """.utf8)
        try legacyCacheData.write(to: support.appending(path: "usage-cache.json"))
        let legacyCacheStore = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let legacyCache = try await legacyCacheStore.loadUsageCache()
        try require(
            legacyCache.entries.first?.usage.fiveHourRemainingPercent == nil,
            "weekly-only usage cache compatibility"
        )

        let settingsURL = support.appending(path: "settings.json")
        try Data(#"{"language":"english"}"#.utf8).write(to: settingsURL)
        let legacySettings = try await store.loadSettings()
        try require(legacySettings.language == .english, "legacy settings language")
        try require(
            legacySettings.showsMenuBarPercentage,
            "legacy settings enable menu bar percentage"
        )
        try require(
            !legacySettings.showsFiveHourUsage,
            "legacy settings hide five-hour usage"
        )
        try require(
            legacySettings.accountNameStyle == .email,
            "legacy settings default to full email labels"
        )
        try require(
            legacySettings.showsTokenActivity,
            "legacy settings show token activity"
        )
        try require(
            !legacySettings.automaticWarmupEnabled,
            "legacy settings keep scheduled warmup disabled"
        )
        try require(
            !legacySettings.fiveHourResetNotificationsEnabled,
            "legacy settings keep reset notifications disabled"
        )
        let directTarget = UUID()
        let currentTarget = UUID()
        try require(
            NotificationSwitchPolicy.disposition(
                targetID: directTarget,
                activeID: currentTarget,
                isMutating: false,
                taskState: .idle
            ) == .direct,
            "notification switch permits only confirmed idle direct switching"
        )
        try require(
            NotificationSwitchPolicy.disposition(
                targetID: directTarget,
                activeID: currentTarget,
                isMutating: false,
                taskState: .unknown
            ) == .confirmUnknown,
            "unknown task state requires confirmation"
        )
        try require(
            DesktopTaskSafetyPolicy.effectiveState(
                desktopIsRunning: true,
                independentlyObservedState: .idle
            ) == .unknown,
            "an independent idle result cannot prove running Desktop is idle"
        )
        let hiddenPercentageSettings = AppSettings(
            language: .simplifiedChinese,
            showsMenuBarPercentage: false,
            showsFiveHourUsage: true
        )
        try await store.saveSettings(hiddenPercentageSettings)
        let reloadedSettingsStore = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let reloadedSettings = try await reloadedSettingsStore.loadSettings()
        try require(
            reloadedSettings == hiddenPercentageSettings,
            "menu bar percentage setting persistence"
        )
        let settingsPermissions = try permissions(settingsURL)
        try require(settingsPermissions == 0o600, "settings permissions")

        let warmupHistoryURL = support.appending(path: "warmup-history.json")
        try Data("""
        {"lastAttemptDayByProfile":{"\(first.id.uuidString)":"2026-09-03"}}
        """.utf8).write(to: warmupHistoryURL)
        let legacyWarmupHistory = try await store.loadWarmupHistory()
        try require(
            legacyWarmupHistory.lastRecordByProfile.isEmpty,
            "legacy warmup history defaults observable results"
        )
        try await store.recordWarmupAttempt(profileID: first.id, day: "2026-09-04")
        let warmupHistory = try await store.loadWarmupHistory()
        try require(
            warmupHistory.lastAttemptDayByProfile[first.id.uuidString] == "2026-09-04",
            "warmup attempt history persistence"
        )
        try require(
            warmupHistory.lastRecordByProfile[first.id.uuidString]?.outcome == .attempting,
            "warmup observable result persistence"
        )
        let warmupHistoryPermissions = try permissions(
            warmupHistoryURL
        )
        try require(warmupHistoryPermissions == 0o600, "warmup history permissions")

        try fileManager.removeItem(at: activeCredential)
        try fileManager.createDirectory(at: activeCredential, withIntermediateDirectories: false)
        do {
            try await store.activateTargetCredential(id: second.id)
            throw CheckFailure.failed("credential rename failure")
        } catch is POSIXError {
            let names = try fileManager.contentsOfDirectory(atPath: activeHome.path)
            try require(
                !names.contains(where: { $0.hasPrefix("auth.json.switcher-") }),
                "failed credential write cleanup"
            )
        }
        try fileManager.removeItem(at: activeCredential)
        try secondBytes.write(to: activeCredential)

        let recorder = Recorder()
        let switcher = SwitchCoordinator(
            desktop: FakeDesktop(recorder: recorder),
            store: FakeStore(recorder: recorder, original: first, target: second),
            codex: FakeCodex(recorder: recorder, target: second),
            recovery: SwitchRecoveryStore(
                baseURL: root.appending(path: "core-switch-recovery"),
                keyProvider: CoreRollbackKeyProvider()
            ),
            operationGate: AccountOperationGate()
        )
        try await switcher.switchAccount(to: second.id)
        let recordedStages = await recorder.snapshot()
        try require(recordedStages == SwitchStage.allCases, "switch stage order")

        let encryptedRecoveryRoot = root.appending(
            path: "encrypted-recovery-check",
            directoryHint: .isDirectory
        )
        let encryptedRecovery = SwitchRecoveryStore(
            baseURL: encryptedRecoveryRoot,
            keyProvider: CoreRollbackKeyProvider()
        )
        let recoverySecret = Data("core-secret-must-remain-encrypted".utf8)
        let encryptedJournal = try await encryptedRecovery.prepare(
            originalCredential: recoverySecret,
            originalAccountID: first.id,
            targetAccountID: second.id,
            desktopWasRunning: true
        )
        let encryptedBackupURL = encryptedRecoveryRoot.appending(
            path: encryptedJournal.backupFileName
        )
        let encryptedBytes = try Data(contentsOf: encryptedBackupURL)
        try require(
            !String(decoding: encryptedBytes, as: UTF8.self).contains(
                "core-secret-must-remain-encrypted"
            ),
            "rollback credential is encrypted"
        )
        let decryptedRecoverySecret = try await encryptedRecovery.loadOriginalCredential(
            for: encryptedJournal
        )
        try require(decryptedRecoverySecret == recoverySecret, "encrypted rollback credential round trip")
        let encryptedBackupPermissions = try permissions(encryptedBackupURL)
        try require(encryptedBackupPermissions == 0o600, "encrypted backup permissions")
        try await encryptedRecovery.clear(encryptedJournal)

        let recoveryOriginal = AccountProfile(
            id: UUID(), displayName: "Recovery Original", email: "recovery-original@example.com",
            accountID: "recovery-original", createdAt: Date(), lastUsedAt: nil
        )
        let recoveryTarget = AccountProfile(
            id: UUID(), displayName: "Recovery Target", email: "recovery-target@example.com",
            accountID: "recovery-target", createdAt: Date(), lastUsedAt: nil
        )
        let interruptedStore = CoreRecoveryStore(
            original: recoveryOriginal,
            target: recoveryTarget
        )
        let interruptedDesktop = CoreRecoveryDesktop()
        let interruptedRecovery = SwitchRecoveryStore(
            baseURL: root.appending(path: "interrupted-recovery-check"),
            keyProvider: CoreRollbackKeyProvider()
        )
        let recoveryOriginalBytes = interruptedStore.originalBytes
        let interruptedJournal = try await interruptedRecovery.prepare(
            originalCredential: recoveryOriginalBytes,
            originalAccountID: recoveryOriginal.id,
            targetAccountID: recoveryTarget.id,
            desktopWasRunning: true
        )
        _ = try await interruptedRecovery.update(interruptedJournal, phase: .targetActivated)
        await interruptedStore.simulateInterruptedActivation()
        let interruptedCoordinator = SwitchCoordinator(
            desktop: interruptedDesktop,
            store: interruptedStore,
            codex: CoreRecoveryCodex(
                store: interruptedStore,
                original: recoveryOriginal,
                target: recoveryTarget
            ),
            recovery: interruptedRecovery,
            operationGate: AccountOperationGate()
        )
        try await interruptedCoordinator.recoverIfNeeded()
        let recoveredAccountID = await interruptedStore.activeAccountID()
        let recoveredCredential = await interruptedStore.activeCredential()
        let remainingJournal = try await interruptedRecovery.loadJournal()
        let recoveryReopenCount = await interruptedDesktop.reopenCount()
        try require(
            recoveredAccountID == recoveryOriginal.id,
            "startup recovery restores original registry"
        )
        try require(
            recoveredCredential == recoveryOriginalBytes,
            "startup recovery restores exact credential"
        )
        try require(
            remainingJournal == nil,
            "startup recovery clears journal after verification"
        )
        try require(
            recoveryReopenCount == 1,
            "startup recovery restores Desktop running state"
        )

        let operationGate = AccountOperationGate()
        let concurrencyProbe = CoreConcurrencyProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await operationGate.run {
                        await concurrencyProbe.enter()
                        try? await Task.sleep(for: .milliseconds(20))
                        await concurrencyProbe.leave()
                    }
                }
            }
        }
        let maximumConcurrency = await concurrencyProbe.maximumConcurrency()
        try require(maximumConcurrency == 1, "account operation gate serializes across await")

        let fakeCodex = root.appending(path: "fake-codex")
        try createExecutable(at: fakeCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 12
              i=0
              while [ "$i" -lt 10000 ]; do
                printf '%s\\n' 'diagnostic output' >&2
                i=$((i + 1))
              done
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *usage*read*) printf '%s\\n' '{"id":1,"result":{"dailyUsageBuckets":[{"startDate":"2026-09-04","tokens":2300}]}}' ;;
            *thread*list*) printf '%s\\n' '{"id":1,"result":{"data":[{"status":{"type":"active","activeFlags":["waitingOnTool"]}}],"nextCursor":null}}' ;;
            *account*read*)
              test "$state" -eq 2 || exit 13
              printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}'
              ;;
          esac
        done
        """)
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fakeCodex),
            requestTimeout: .seconds(3)
        )
        let rpcWeekly = try await client.readWeeklyUsage(profileHome: root)
        try require(rpcWeekly.remainingPercent == 42, "JSONL rate-limit handshake")
        try require(rpcWeekly.fiveHourRemainingPercent == 20, "JSONL five-hour rate limit")
        let rpcActivity = try await client.readTokenActivity(profileHome: root)
        try require(
            rpcActivity.dailyBuckets == [
                DailyTokenUsage(startDate: "2026-09-04", tokens: 2300),
            ],
            "JSONL official daily token buckets"
        )
        let rpcTaskState = try await client.readDesktopTaskState(profileHome: root)
        try require(
            rpcTaskState == .active(count: 1),
            "official thread status blocks direct notification switching"
        )

        let nullUsageCodex = root.appending(path: "null-usage-codex")
        try createExecutable(at: nullUsageCodex, body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *usage*read*) printf '%s\\n' '{"id":1,"result":{"dailyUsageBuckets":null}}' ;;
          esac
        done
        """)
        let nullUsageClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: nullUsageCodex),
            requestTimeout: .seconds(3)
        )
        do {
            _ = try await nullUsageClient.readTokenActivity(profileHome: root)
            throw CheckFailure.failed("null daily buckets should be unavailable")
        } catch let error as CodexClientError {
            try require(error == .tokenActivityUnavailable, "null daily buckets stay unavailable")
        }
        let identity = try await client.readIdentity(profileHome: root)
        try require(identity.accountID == "acct-123", "JSONL account handshake")

        let warmupCodex = root.appending(path: "warmup-codex")
        try createExecutable(at: warmupCodex, body: """
        if test "${1:-}" = "exec"; then
          case " $* " in
            *" --model gpt-5.6-luna "*) exit 0 ;;
            *) exit 21 ;;
          esac
        fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-sol"},{"model":"gpt-5.6-luna"}]}}' ;;
          esac
        done
        """)
        let warmupClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: warmupCodex),
            requestTimeout: .seconds(3)
        )
        let warmupModel = try await warmupClient.warmup(profileHome: root)
        try require(
            warmupModel == "gpt-5.6-luna",
            "warmup discovers and invokes the smaller available model"
        )

        let largeOnlyCodex = root.appending(path: "large-only-codex")
        try createExecutable(at: largeOnlyCodex, body: """
        if test "${1:-}" = "exec"; then exit 31; fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-sol"}]}}' ;;
          esac
        done
        """)
        let largeOnlyClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: largeOnlyCodex),
            requestTimeout: .seconds(3)
        )
        do {
            _ = try await largeOnlyClient.warmup(profileHome: root)
            throw CheckFailure.failed("warmup should not use an unverified large model")
        } catch let error as CodexClientError {
            try require(
                error == .warmupFailed("No verified small model is available."),
                "warmup skips when no verified small model is available"
            )
        }

        let stalledWarmupCodex = root.appending(path: "stalled-warmup-codex")
        try createExecutable(at: stalledWarmupCodex, body: """
        if test "${1:-}" = "exec"; then
          sleep 5
          exit 0
        fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-luna"}]}}' ;;
          esac
        done
        """)
        let stalledWarmupClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: stalledWarmupCodex),
            requestTimeout: .milliseconds(100)
        )
        do {
            _ = try await stalledWarmupClient.warmup(profileHome: root)
            throw CheckFailure.failed("stalled warmup should time out")
        } catch let error as CodexClientError {
            try require(error == .timeout, "stalled warmup timeout")
        }

        let notificationService = CoreNotificationService()
        let appModel = AppModel(
            store: store,
            codex: client,
            switchService: ReopenFailureSwitchService(store: store),
            operationGate: AccountOperationGate(),
            localSessionScanner: LocalSessionUsageScanner(codexHome: root),
            notificationService: notificationService
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { await appModel.start() }
            }
        }
        try require(
            !appModel.accounts.isEmpty,
            "concurrent startup callers await one completed initialization"
        )
        await appModel.setFiveHourResetNotificationsEnabled(true)
        try require(
            appModel.settings.fiveHourResetNotificationsEnabled,
            "authorized reset reminders can be enabled"
        )
        let notificationAuthorizationRequestCount = await notificationService.requestCount()
        try require(
            notificationAuthorizationRequestCount == 1,
            "notification authorization is requested on enable"
        )
        try require(
            appModel.usageStates[first.id] == .loaded(cachedWeekly),
            "cached usage is visible at startup"
        )
        await appModel.setShowsFiveHourUsage(false)
        try require(
            !appModel.settings.showsFiveHourUsage,
            "five-hour setting updates immediately"
        )
        appModel.refreshWeeklyUsage()
        try require(
            appModel.usageStates[first.id] == .loaded(cachedWeekly),
            "refresh keeps cached usage visible"
        )
        await appModel.waitForWeeklyUsageRefresh()
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.remainingPercent == 42,
            "refresh replaces displayed cached usage"
        )
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.fiveHourRemainingPercent == 20,
            "hidden five-hour usage is still normalized"
        )
        try require(
            appModel.activeRemainingPercent == 42,
            "menu-bar percentage remains weekly"
        )
        let refreshedCache = try await store.loadUsageCache()
        try require(
            refreshedCache.entries.first(where: { $0.profileID == first.id })?.usage.remainingPercent == 42,
            "refresh replaces persisted cached usage"
        )
        try require(
            refreshedCache.entries.first(where: { $0.profileID == first.id })?.usage.fiveHourRemainingPercent == 20,
            "hidden five-hour usage is still cached"
        )

        let requestCountURL = root.appending(path: "rate-limit-request-count")
        let countingCodex = root.appending(path: "counting-codex")
        try createExecutable(at: countingCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 15
              printf '%s\\n' 'request' >> '\(requestCountURL.path)'
              sleep 1
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":57,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *usage*read*) printf '%s\\n' '{"id":1,"result":{"dailyUsageBuckets":[]}}' ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        let countingClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: countingCodex),
            requestTimeout: .seconds(3)
        )
        let countingModel = AppModel(
            store: store,
            codex: countingClient,
            switchService: ReopenFailureSwitchService(store: store),
            operationGate: AccountOperationGate(),
            localSessionScanner: LocalSessionUsageScanner(codexHome: root)
        )
        await countingModel.start()
        try require(countingModel.accounts.count == 3, "counting model loaded all profiles")

        countingModel.refreshWeeklyUsage()
        try await waitForLineCount(at: requestCountURL, atLeast: 3)
        countingModel.refreshWeeklyUsage()
        await countingModel.waitForWeeklyUsageRefresh()
        try require(lineCount(at: requestCountURL) == 3, "in-flight refresh stays single-flight")

        countingModel.refreshWeeklyUsage()
        await countingModel.waitForWeeklyUsageRefresh()
        try require(lineCount(at: requestCountURL) == 6, "next popover refresh starts a new request round")

        countingModel.refreshWeeklyUsage()
        try await waitForLineCount(at: requestCountURL, atLeast: 9)
        await countingModel.removeAccount(id: third.id)
        await countingModel.waitForWeeklyUsageRefresh()
        try require(countingModel.usageStates[third.id] == nil, "deleted profile stays absent from usage state")
        let cacheAfterDeletion = try await store.loadUsageCache()
        try require(
            !cacheAfterDeletion.entries.contains(where: { $0.profileID == third.id }),
            "deleted profile is not revived in usage cache"
        )

        let scheduledRequestCountURL = root.appending(path: "scheduled-rate-limit-request-count")
        let scheduledCodex = root.appending(path: "scheduled-codex")
        try createExecutable(at: scheduledCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 16
              printf '%s\\n' 'request' >> '\(scheduledRequestCountURL.path)'
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":56,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *usage*read*) printf '%s\\n' '{"id":1,"result":{"dailyUsageBuckets":[]}}' ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        let scheduledClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: scheduledCodex),
            requestTimeout: .seconds(3)
        )
        let scheduledModel = AppModel(
            store: store,
            codex: scheduledClient,
            switchService: ReopenFailureSwitchService(store: store),
            operationGate: AccountOperationGate(),
            localSessionScanner: LocalSessionUsageScanner(codexHome: root)
        )
        await scheduledModel.startBackgroundUsageRefresh(every: .seconds(3))
        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 2)
        await scheduledModel.waitForWeeklyUsageRefresh()

        try await Task.sleep(for: .seconds(1))
        scheduledModel.refreshWeeklyUsage()
        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 4)
        await scheduledModel.waitForWeeklyUsageRefresh()

        try await Task.sleep(for: .milliseconds(2_500))
        try require(
            lineCount(at: scheduledRequestCountURL) == 4,
            "manual refresh postpones the previously scheduled refresh"
        )

        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 6)
        await scheduledModel.waitForWeeklyUsageRefresh()
        scheduledModel.stopBackgroundUsageRefresh()
        let countAfterBackgroundCancellation = lineCount(at: scheduledRequestCountURL)
        scheduledModel.refreshWeeklyUsage()
        try await waitForLineCount(
            at: scheduledRequestCountURL,
            atLeast: countAfterBackgroundCancellation + 2
        )
        await scheduledModel.waitForWeeklyUsageRefresh()
        let countAfterStoppedManualRefresh = lineCount(at: scheduledRequestCountURL)
        try await Task.sleep(for: .milliseconds(3_200))
        try require(
            lineCount(at: scheduledRequestCountURL) == countAfterStoppedManualRefresh,
            "manual refresh does not restart a stopped background schedule"
        )

        let usageCacheURL = support.appending(path: "usage-cache.json")
        guard Darwin.chflags(usageCacheURL.path, UInt32(UF_IMMUTABLE)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let cacheWriteError: (any Error)?
        do {
            try await store.cacheWeeklyUsage(
                WeeklyUsage(remainingPercent: 99, resetsAt: cachedWeekly.resetsAt),
                profileID: first.id
            )
            cacheWriteError = nil
        } catch {
            cacheWriteError = error
        }
        guard Darwin.chflags(usageCacheURL.path, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try require(cacheWriteError is POSIXError, "immutable cache file rejects atomic replacement")
        let cacheAfterFailedWrite = try await AccountStore(
            baseURL: support,
            activeHomeURL: activeHome
        ).loadUsageCache()
        try require(
            cacheAfterFailedWrite.entries.first(where: { $0.profileID == first.id })?.usage.remainingPercent == 44,
            "failed cache replacement preserves the previous complete file"
        )
        let cacheTemporaryFiles = try fileManager.contentsOfDirectory(atPath: support.path)
            .filter { $0.hasPrefix("usage-cache.json.switcher-") }
        try require(cacheTemporaryFiles.isEmpty, "failed cache replacement removes temporary file")

        try require(!appModel.activeIdentityConfirmed, "precondition identity mismatch")
        await appModel.switchAccount(to: second.id)
        try require(appModel.activeAccountID == second.id, "reopen failure active account reload")
        try require(appModel.activeIdentityConfirmed, "reopen failure identity state")
        try require(appModel.visibleError?.stage == .reopenDesktop, "reopen failure message stage")

        let failingCodex = root.appending(path: "failing-codex")
        try createExecutable(at: failingCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
            *rateLimits*) exit 14 ;;
          esac
        done
        """)
        let failingClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: failingCodex),
            requestTimeout: .seconds(2)
        )
        let failureModel = AppModel(
            store: store,
            codex: failingClient,
            switchService: ReopenFailureSwitchService(store: store),
            operationGate: AccountOperationGate(),
            localSessionScanner: LocalSessionUsageScanner(codexHome: root)
        )
        await failureModel.start()
        failureModel.refreshWeeklyUsage()
        await failureModel.waitForWeeklyUsageRefresh()
        try require(
            failureModel.usageStates[first.id]?.displayedUsage?.remainingPercent == 44,
            "failed refresh retains cached usage"
        )
        try require(
            failureModel.usageStates[first.id]?.refreshError != nil,
            "failed refresh exposes stale-cache warning"
        )

        let stalledCodex = root.appending(path: "stalled-codex")
        try createExecutable(at: stalledCodex, body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *account*read*) sleep 5 ;;
          esac
        done
        """)
        let stalledClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: stalledCodex),
            requestTimeout: .milliseconds(50)
        )
        do {
            _ = try await stalledClient.readIdentity(profileHome: root)
            throw CheckFailure.failed("app-server timeout")
        } catch CodexClientError.timeout {
            // Expected: the first deadline stops the request without retrying.
        }

        print("Core checks passed")
    }
}
