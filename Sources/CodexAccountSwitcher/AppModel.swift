import AppKit
import Foundation
import ServiceManagement
import SwiftUI

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage?, TokenActivity?, String?, String?, Date?, String?)
    case failure(UUID, String)
}

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum ActiveIdentityVerificationState: Equatable {
    case checking
    case confirmed
    case unavailable
    case mismatch
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [AccountProfile] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var usageStates: [UUID: UsageViewState] = [:]
    @Published private(set) var tokenActivities: [UUID: TokenActivity] = [:]
    @Published private(set) var tokenFetchedAt: [UUID: Date] = [:]
    @Published private(set) var tokenRefreshPending: Set<UUID> = []
    @Published private(set) var tokenActivityRefreshFinished = false
    @Published private(set) var tokenRefreshErrors: [UUID: String] = [:]
    @Published private(set) var localTokenSnapshot: LocalTokenUsageSnapshot?
    @Published private(set) var warmupStatuses: [UUID: WarmupRecord] = [:]
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var switchProgress: SwitchProgress = .stoppingRequests
    @Published private(set) var switchingAccount: AccountProfile?
    @Published private(set) var switchedAccount: AccountProfile?
    @Published private(set) var isMutating = false
    @Published private(set) var isAddingAccount = false
    @Published private(set) var isSavingSettings = false
    @Published var visibleError: OperationError?
    @Published private(set) var activeIdentityState: ActiveIdentityVerificationState = .checking
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled

    private let store: AccountStore
    private let codex: CodexClient
    private let loginService: any LoginServicing
    private let switchService: any SwitchServicing
    private let desktop: any DesktopControlling
    private let taskStateReader: any DesktopTaskStateReading
    private let notificationService: any QuotaNotificationServicing
    private let operationGate: AccountOperationGate
    private let localUsageScanner: LocalSessionUsageScanner?
    private var hasStarted = false
    private var startTask: Task<Void, Never>?
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(30)
    private var isBackgroundUsageRefreshEnabled = false
    private var lastNotifiedFiveHourResetAt: [UUID: Date] = [:]

    init(
        store: AccountStore,
        codex: CodexClient,
        switchService: any SwitchServicing,
        operationGate: AccountOperationGate,
        desktop: any DesktopControlling = DesktopController(),
        taskStateReader: (any DesktopTaskStateReading)? = nil,
        notificationService: any QuotaNotificationServicing = InertQuotaNotificationService(),
        loginService: (any LoginServicing)? = nil,
        localUsageScanner: LocalSessionUsageScanner? = nil
    ) {
        self.store = store
        self.codex = codex
        self.loginService = loginService ?? codex
        self.switchService = switchService
        self.operationGate = operationGate
        self.desktop = desktop
        self.taskStateReader = taskStateReader ?? codex
        self.notificationService = notificationService
        self.localUsageScanner = localUsageScanner
    }

    static func live() -> AppModel {
        let store = AccountStore()
        let codex = CodexClient()
        let operationGate = AccountOperationGate()
        let recovery = SwitchRecoveryStore()
        let desktop = DesktopController()
        return AppModel(
            store: store,
            codex: codex,
            switchService: SwitchCoordinator(
                desktop: desktop,
                store: store,
                codex: codex,
                recovery: recovery,
                operationGate: operationGate
            ),
            operationGate: operationGate,
            desktop: desktop,
            notificationService: QuotaNotificationService(),
            localUsageScanner: LocalSessionUsageScanner()
        )
    }

    func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    var activeShowsFiveHour: Bool {
        accounts.first { $0.id == activeAccountID }?.supportsFiveHourUsage ?? true
    }

    var menuBarQuota: MenuBarQuotaPresentation {
        MenuBarQuotaPresentation(
            state: activeAccountID.flatMap { usageStates[$0] },
            identityConflict: activeIdentityState == .mismatch,
            showsFiveHour: activeShowsFiveHour
        )
    }

    var activeRemainingPercent: Int? {
        guard let activeAccountID else { return nil }
        return usageStates[activeAccountID]?.displayedUsage?.remainingPercent
    }

    var activeAccountLabel: String? {
        guard let activeAccountID else { return nil }
        return accounts.first(where: { $0.id == activeAccountID })?.preferredLabel
    }

    var commonTokenDateKey: String? {
        guard !accounts.isEmpty else { return nil }
        let activities = accounts.compactMap { tokenActivities[$0.id] }
        guard activities.count == accounts.count else { return nil }
        return TokenActivity.latestCommonDateKey(in: activities)
    }

    /// The UI's primary Token row always names the current Beijing natural day.
    /// A missing bucket never causes an older server day to replace it.
    var tokenReportingDate: String? {
        TokenActivity.dateKey()
    }

    var reportedTokenTotal: Int? {
        localTokenSnapshot?.todayTokens
    }

    var reportedTokenCoverage: (Int, Int) {
        let today = TokenActivity.dateKey()
        let count = accounts.reduce(into: 0) { count, account in
            guard tokenActivities[account.id]?.tokens(on: today) != nil else { return }
            count += 1
        }
        return (count, accounts.count)
    }

    var activeIdentityConfirmed: Bool {
        activeIdentityState == .confirmed
    }

    var displayedAccounts: [AccountProfile] {
        accounts.sorted { lhs, rhs in
            if lhs.id == rhs.id { return false }
            if lhs.id == activeAccountID { return true }
            if rhs.id == activeAccountID { return false }
            return (lhs.lastUsedAt ?? lhs.createdAt) > (rhs.lastUsedAt ?? rhs.createdAt)
        }
    }

    var launchesAtLogin: Bool {
        launchAtLoginState.isOn
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginState == .requiresApproval
    }

    var launchAtLoginUnavailable: Bool {
        launchAtLoginState == .unavailable
    }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startTask = task
        await task.value
    }

    private func performStart() async {
        guard !hasStarted else { return }
        hasStarted = true
        await localUsageScanner?.start { [weak self] snapshot in
            self?.localTokenSnapshot = snapshot
        }
        refreshLaunchAtLoginStatus()
        do {
            let recoveryWarning: OperationError?
            do {
                try await switchService.recoverIfNeeded()
                recoveryWarning = nil
            } catch let error as OperationError {
                // A committed target remains authoritative. Its verification,
                // Desktop reopen, or journal cleanup warning must not prevent
                // the account registry and settings from loading.
                recoveryWarning = error
            }
            settings = try await store.loadSettings()
            var registry = try await store.loadRegistry()
            if registry.accounts.isEmpty, await store.activeCredentialExists() {
                let activeHome = await store.activeCodexHome()
                let identity = try await codex.readIdentity(profileHome: activeHome)
                let profile = AccountProfile(
                    id: UUID(),
                    displayName: identity.email ?? identity.suggestedDisplayName,
                    email: identity.email,
                    accountID: identity.accountID,
                    planType: identity.planType,
                    createdAt: Date(),
                    lastUsedAt: Date()
                )
                try await store.importCurrentProfile(profile)
                registry = try await store.loadRegistry()
            }
            apply(registry)
            do {
                apply(try await store.loadUsageCache())
            } catch {
                showError(error)
            }
            do {
                let history = try await store.loadWarmupHistory()
                warmupStatuses = history.lastRecordByProfile.reduce(into: [:]) { values, item in
                    guard let id = UUID(uuidString: item.key) else { return }
                    values[id] = item.value
                }
            } catch {
                showError(error)
            }
            await confirmActiveIdentity()
            if let recoveryWarning {
                visibleError = recoveryWarning
            }
        } catch {
            showError(error)
        }
    }

    func refreshWeeklyUsage() {
        if isBackgroundUsageRefreshEnabled {
            scheduleNextWeeklyUsageRefresh()
        }
        guard !accounts.isEmpty, !isMutating, usageRefreshTask == nil else { return }
        tokenActivityRefreshFinished = false
        tokenRefreshPending = Set(accounts.map(\.id))
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
        }
    }

    func refreshLocalTokenUsage() {
        Task { [weak self] in
            guard let self else { return }
            self.localTokenSnapshot = await self.localUsageScanner?.refresh()
        }
    }

    func stopLocalTokenMonitoring() async {
        await localUsageScanner?.stop()
    }

    func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    func startBackgroundUsageRefresh(every interval: Duration = .seconds(30)) async {
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        await start()
        refreshWeeklyUsage()
    }

    func stopBackgroundUsageRefresh() {
        isBackgroundUsageRefreshEnabled = false
        nextUsageRefreshTask?.cancel()
        nextUsageRefreshTask = nil
        Task { [localUsageScanner] in await localUsageScanner?.stop() }
    }

    private func scheduleNextWeeklyUsageRefresh() {
        nextUsageRefreshTask?.cancel()
        let interval = backgroundUsageRefreshInterval
        nextUsageRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.nextUsageRefreshTask = nil
            self.refreshWeeklyUsage()
        }
    }

    private func performWeeklyUsageRefresh() async {
        let targets = await withTaskGroup(of: (UUID, URL).self, returning: [(UUID, URL)].self) { group in
            for account in accounts {
                group.addTask { [store] in
                    (account.id, await store.profileHome(id: account.id))
                }
            }
            var values: [(UUID, URL)] = []
            for await value in group { values.append(value) }
            return values
        }

        await withTaskGroup(of: UsageRefreshResult.self) { group in
            for (id, home) in targets {
                group.addTask { [codex, operationGate] in
                    do {
                        let values = try await operationGate.run {
                            let usage: WeeklyUsage?
                            let quotaError: String?
                            do {
                                usage = try await codex.readWeeklyUsage(profileHome: home)
                                quotaError = nil
                            } catch {
                                usage = nil
                                quotaError = error.localizedDescription
                            }
                            let tokens: TokenActivity?
                            let tokenError: String?
                            let tokenFetchedAt: Date?
                            do {
                                tokens = try await codex.readTokenActivity(profileHome: home)
                                tokenError = nil
                                tokenFetchedAt = Date()
                            } catch {
                                tokens = nil
                                tokenError = error.localizedDescription
                                tokenFetchedAt = nil
                            }
                            let identity = try? await codex.readIdentity(profileHome: home)
                            return (usage, tokens, identity?.planType, tokenError, tokenFetchedAt, quotaError)
                        }
                        return .success(id, values.0, values.1, values.2, values.3, values.4, values.5)
                    } catch {
                        return .failure(id, error.localizedDescription)
                    }
                }
            }
            for await result in group {
                // Cancellation is a foreground handoff, not a quota failure.
                guard !Task.isCancelled else { continue }
                switch result {
                case let .success(id, usage, activity, planType, tokenError, fetchedAt, quotaError):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    tokenRefreshErrors[id] = tokenError
                    tokenRefreshPending.remove(id)
                    let previousUsage = usageStates[id]?.displayedUsage
                    if let usage {
                        usageStates[id] = .loaded(usage)
                    } else if let quotaError {
                        usageStates[id] = previousUsage.map { .stale($0, quotaError) } ?? .unavailable(quotaError)
                    }
                    if let activity {
                        // Publish each successful token response before cache
                        // persistence and before the remaining accounts finish.
                        tokenActivities[id] = activity
                        if let fetchedAt {
                            tokenFetchedAt[id] = fetchedAt
                        }
                    }
                    do {
                        if let usage { try await store.cacheWeeklyUsage(usage, profileID: id) }
                        if let activity, let fetchedAt {
                            try await store.cacheTokenActivity(
                                activity,
                                profileID: id,
                                fetchedAt: fetchedAt
                            )
                        }
                        if let planType {
                            try await store.updatePlanType(id: id, planType: planType)
                            if let index = accounts.firstIndex(where: { $0.id == id }) {
                                accounts[index].planType = planType
                            }
                        }
                        if let usage {
                            await notifyIfFiveHourResetReached(
                                profileID: id,
                                previousUsage: previousUsage,
                                currentUsage: usage
                            )
                        }
                    } catch {
                        showError(error)
                    }
                case let .failure(id, message):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    tokenRefreshErrors[id] = message
                    tokenRefreshPending.remove(id)
                    if let cached = usageStates[id]?.displayedUsage {
                        usageStates[id] = .stale(cached, message)
                    } else {
                        usageStates[id] = .unavailable(message)
                    }
                }
            }
        }
        tokenRefreshPending.removeAll()
        tokenActivityRefreshFinished = true
        await performScheduledWarmupIfNeeded()
    }

    private func performScheduledWarmupIfNeeded(now: Date = Date()) async {
        guard !Task.isCancelled, settings.automaticWarmupEnabled else { return }
        let calendar = Calendar.current
        guard let scheduled = calendar.date(
            bySettingHour: settings.warmupHour,
            minute: settings.warmupMinute,
            second: 0,
            of: now
        ), now >= scheduled else { return }

        let day = Self.localDayString(now, calendar: calendar)
        let history: WarmupHistory
        do {
            history = try await store.loadWarmupHistory()
        } catch {
            showError(error)
            return
        }

        for account in displayedAccounts {
            guard !Task.isCancelled else { return }
            guard history.lastAttemptDayByProfile[account.id.uuidString] != day else { continue }
            guard case let .loaded(currentUsage) = usageStates[account.id] else { continue }
            guard currentUsage.allowsWarmup(at: now) else { continue }

            do {
                // Persist before the network request so an app restart cannot duplicate a warmup.
                try await store.recordWarmupAttempt(
                    profileID: account.id,
                    day: day,
                    attemptedAt: now
                )
                warmupStatuses[account.id] = WarmupRecord(
                    attemptedAt: now,
                    outcome: .attempting,
                    model: nil
                )
                let result = try await operationGate.run { [codex, store] in
                    let registry = try await store.loadRegistry()
                    let isActive = registry.activeAccountID == account.id
                    let home = isActive
                        ? await store.activeCodexHome()
                        : await store.profileHome(id: account.id)
                    let model = try await codex.warmup(profileHome: home)
                    do {
                        if isActive {
                            try await store.saveCurrentCredential()
                        }
                        let usage = try await codex.readWeeklyUsage(profileHome: home)
                        return (model, Optional(usage))
                    } catch {
                        return (model, nil)
                    }
                }
                if let usage = result.1 {
                    usageStates[account.id] = .loaded(usage)
                    try await store.cacheWeeklyUsage(usage, profileID: account.id)
                }
                let isConfirmed = result.1?.fiveHourResetsAt.map { $0 > now } == true
                let record = WarmupRecord(
                    attemptedAt: now,
                    outcome: isConfirmed ? .confirmed : .unconfirmed,
                    model: result.0
                )
                warmupStatuses[account.id] = record
                try await store.recordWarmupResult(profileID: account.id, record: record)
            } catch {
                let record = WarmupRecord(
                    attemptedAt: now,
                    outcome: .failed,
                    model: nil
                )
                warmupStatuses[account.id] = record
                try? await store.recordWarmupResult(profileID: account.id, record: record)
                if !Task.isCancelled { showError(error) }
            }
        }
    }

    func switchAccount(to id: UUID) async {
        guard id != activeAccountID, !isMutating, !isAddingAccount else { return }
        guard let target = accounts.first(where: { $0.id == id }) else { return }
        dismissSwitchResult()
        switchProgress = .stoppingRequests
        switchingAccount = target
        visibleError = nil
        isMutating = true
        let interruptedRefresh = usageRefreshTask
        interruptedRefresh?.cancel()
        // Keep the gate until the cancelled request (including any warmup)
        // has stopped. No credential writes may overlap the old process.
        await interruptedRefresh?.value
        defer {
            switchingAccount = nil
            isMutating = false
            if interruptedRefresh != nil { refreshWeeklyUsage() }
        }
        do {
            try await switchService.switchAccount(to: id) { [weak self] phase in
                await MainActor.run { self?.switchProgress = phase }
            }
            apply(try await store.loadRegistry())
            activeIdentityState = .confirmed
            switchedAccount = target
            scheduleSwitchResultDismissal()
        } catch let error as OperationError {
            if error.stage == .reopenDesktop {
                do {
                    apply(try await store.loadRegistry())
                    activeIdentityState = .confirmed
                } catch {
                    showError(error)
                    return
                }
                visibleError = OperationError(
                    stage: .reopenDesktop,
                    titleKey: "switched_reopen_title",
                    messageKey: nil,
                    message: error.message,
                    underlyingDescription: error.underlyingDescription
                )
            } else {
                visibleError = error
                // An error can occur after the switch commits (for example,
                // journal cleanup). Reconcile the saved identity before drawing
                // the current-account badge or menu-bar quota again.
                do {
                    apply(try await store.loadRegistry())
                    await confirmActiveIdentity()
                } catch let refreshError {
                    activeIdentityState = .unavailable
                    visibleError = OperationError(
                        stage: error.stage,
                        titleKey: error.titleKey,
                        messageKey: nil,
                        message: "\(error.localizedDescription) Refreshing account state also failed: \(refreshError.localizedDescription)",
                        underlyingDescription: error.underlyingDescription
                    )
                }
            }
        } catch {
            showError(error)
        }
    }


    private var switchResultTask: Task<Void, Never>?

    private func scheduleSwitchResultDismissal() {
        switchResultTask?.cancel()
        switchResultTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.dismissSwitchResult()
        }
    }

    func dismissSwitchResult() {
        switchResultTask?.cancel()
        switchResultTask = nil
        switchedAccount = nil
    }

    func addAccount() {
        guard !isMutating, !isAddingAccount else { return }
        isAddingAccount = true
        addAccountTask = Task { [weak self] in
            guard let self else { return }
            await self.performAddAccount()
            self.isAddingAccount = false
            self.addAccountTask = nil
        }
    }

    func cancelAddingAccount() {
        addAccountTask?.cancel()
    }

    private func performAddAccount() async {
        let id = UUID()
        var profileCreated = false
        var profileRegistered = false
        do {
            let home = try await store.createProfileDirectory(id: id)
            profileCreated = true
            try Task.checkCancellation()
            let identity = try await operationGate.run { [loginService] in
                try await loginService.login(profileHome: home)
            }
            try Task.checkCancellation()
            let profile = AccountProfile(
                id: id,
                displayName: identity.email ?? identity.suggestedDisplayName,
                email: identity.email,
                accountID: identity.accountID,
                planType: identity.planType,
                createdAt: Date(),
                lastUsedAt: nil
            )
            try await operationGate.run { [store] in
                try await store.addProfile(profile)
            }
            profileRegistered = true
            apply(try await store.loadRegistry())
        } catch is CancellationError {
            guard profileCreated, !profileRegistered else { return }
            do {
                try await store.removeUnregisteredProfile(id: id)
            } catch {
                showError(error)
            }
        } catch {
            if profileCreated, !profileRegistered {
                do {
                    try await store.removeUnregisteredProfile(id: id)
                } catch let cleanupError {
                    showError(LocalizedAppError(message: "\(error.localizedDescription) Cleanup also failed: \(cleanupError.localizedDescription)"))
                    return
                }
            }
            showError(error)
        }
    }

    func removeAccount(id: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await operationGate.run { [store] in
                try await store.removeAccount(id: id)
            }
            apply(try await store.loadRegistry())
            usageStates[id] = nil
            tokenActivities[id] = nil
            tokenFetchedAt[id] = nil
            tokenRefreshPending.remove(id)
            tokenRefreshErrors[id] = nil
        } catch {
            showError(error)
        }
    }

    func updateNickname(id: UUID, nickname: String?) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await store.updateNickname(id: id, nickname: nickname)
            apply(try await store.loadRegistry())
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func setLanguage(_ language: AppLanguage) async {
        await updateSettings { $0.language = language }
    }

    func setShowsMenuBarPercentage(_ enabled: Bool) async {
        await updateSettings { $0.showsMenuBarPercentage = enabled }
    }

    func setShowsFiveHourUsage(_ enabled: Bool) async {
        await updateSettings { $0.showsFiveHourUsage = enabled }
    }

    func setAccountNameStyle(_ style: AccountNameStyle) async {
        await updateSettings { $0.accountNameStyle = style }
    }

    func setShowsTokenActivity(_ enabled: Bool) async {
        if await updateSettings({ $0.showsTokenActivity = enabled }), enabled { refreshWeeklyUsage() }
    }

    func setAutomaticWarmupEnabled(_ enabled: Bool) async {
        if await updateSettings({ $0.automaticWarmupEnabled = enabled }), enabled { refreshWeeklyUsage() }
    }

    func setFiveHourResetNotificationsEnabled(_ enabled: Bool) async {
        if !enabled {
            await updateSettings { $0.fiveHourResetNotificationsEnabled = false }
            return
        }
        guard !isSavingSettings else { return }
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            guard try await notificationService.requestAuthorization() else {
                showError(LocalizedAppError(message: text("notification_permission_denied")))
                return
            }
            let now = Date()
            for (id, state) in usageStates {
                guard let resetAt = state.displayedUsage?.fiveHourResetsAt, resetAt <= now else { continue }
                lastNotifiedFiveHourResetAt[id] = resetAt
                try await store.markFiveHourResetNotified(profileID: id, resetAt: resetAt)
            }
            var updated = settings
            updated.fiveHourResetNotificationsEnabled = true
            try await store.saveSettings(updated)
            settings = updated
        } catch {
            showError(error)
        }
    }

    func setWarmupTime(_ date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        await updateSettings {
            $0.warmupHour = components.hour ?? 8
            $0.warmupMinute = components.minute ?? 30
        }
    }

    var warmupTime: Date {
        Calendar.current.date(
            bySettingHour: settings.warmupHour,
            minute: settings.warmupMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    @discardableResult
    private func updateSettings(_ update: (inout AppSettings) -> Void) async -> Bool {
        guard !isSavingSettings else { return false }
        isSavingSettings = true
        defer { isSavingSettings = false }
        var updated = settings
        update(&updated)
        do {
            try await store.saveSettings(updated)
            settings = updated
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginState = LaunchAtLoginState(status: SMAppService.mainApp.status)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            showError(error)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func dismissError() {
        visibleError = nil
    }

    private func apply(_ registry: AccountRegistry) {
        accounts = registry.accounts
        activeAccountID = registry.activeAccountID
        usageStates = usageStates.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        tokenRefreshErrors = tokenRefreshErrors.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        tokenRefreshPending = tokenRefreshPending.filter { id in
            registry.accounts.contains(where: { $0.id == id })
        }
        tokenFetchedAt = tokenFetchedAt.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        tokenActivities = tokenActivities.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        warmupStatuses = warmupStatuses.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        lastNotifiedFiveHourResetAt = lastNotifiedFiveHourResetAt.filter {
            id, _ in registry.accounts.contains(where: { $0.id == id })
        }
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            usageStates[entry.profileID] = .loaded(entry.usage)
            if let activity = entry.tokenActivity {
                tokenActivities[entry.profileID] = activity
            }
            if let fetchedAt = entry.tokenFetchedAt {
                tokenFetchedAt[entry.profileID] = fetchedAt
            }
            if let resetAt = entry.lastNotifiedFiveHourResetAt {
                lastNotifiedFiveHourResetAt[entry.profileID] = resetAt
            }
        }
        tokenActivityRefreshFinished = false
    }

    func handleNotificationSwitchRequest(profileID: UUID) async {
        await start()
        guard accounts.contains(where: { $0.id == profileID }) else { return }
        guard !isAddingAccount, !isMutating else {
            showError(LocalizedAppError(message: text("switch_in_progress")))
            return
        }

        let taskState: DesktopTaskState
        if await desktop.isDesktopRunning() {
            do {
                let activeHome = await store.activeCodexHome()
                let observed = try await operationGate.run { [taskStateReader] in
                    try await taskStateReader.readDesktopTaskState(profileHome: activeHome)
                }
                taskState = DesktopTaskSafetyPolicy.effectiveState(
                    desktopIsRunning: true,
                    independentlyObservedState: observed
                )
            } catch {
                taskState = .unknown
            }
        } else {
            taskState = DesktopTaskSafetyPolicy.effectiveState(
                desktopIsRunning: false,
                independentlyObservedState: nil
            )
        }

        switch NotificationSwitchPolicy.disposition(
            targetID: profileID,
            activeID: activeAccountID,
            isMutating: isMutating,
            isAddingAccount: isAddingAccount,
            taskState: taskState
        ) {
        case .noAction:
            return
        case .direct:
            if confirmNotificationSwitch(title: text("confirm_switch"), body: text("switch_body")) {
                await switchAccount(to: profileID)
            }
        case let .confirmActive(count):
            if confirmNotificationSwitch(
                title: text("task_switch_active_title"),
                body: format("task_switch_active_body", String(count))
            ) {
                await switchAccount(to: profileID)
            }
        case .confirmUnknown:
            if confirmNotificationSwitch(
                title: text("task_switch_unknown_title"),
                body: text("task_switch_unknown_body")
            ) {
                await switchAccount(to: profileID)
            }
        case .operationInProgress:
            showError(LocalizedAppError(message: text("switch_in_progress")))
        }
    }

    private func notifyIfFiveHourResetReached(
        profileID: UUID,
        previousUsage: WeeklyUsage?,
        currentUsage: WeeklyUsage
    ) async {
        guard settings.fiveHourResetNotificationsEnabled,
              let resetAt = FiveHourResetDetector.resetToNotify(
                previousUsage: previousUsage,
                currentUsage: currentUsage,
                lastNotifiedResetAt: lastNotifiedFiveHourResetAt[profileID],
                now: Date()
              ),
              let account = accounts.first(where: { $0.id == profileID })
        else { return }

        let label = account.primaryLabel(style: settings.accountNameStyle)
        let previousNotifiedResetAt = lastNotifiedFiveHourResetAt[profileID]
        do {
            lastNotifiedFiveHourResetAt[profileID] = resetAt
            try await store.markFiveHourResetNotified(profileID: profileID, resetAt: resetAt)
            try await notificationService.sendFiveHourResetNotification(
                profileID: profileID,
                accountLabel: label,
                title: text("five_hour_reset_notification_title"),
                body: format("five_hour_reset_notification_body", label),
                resetAt: resetAt
            )
        } catch {
            lastNotifiedFiveHourResetAt[profileID] = previousNotifiedResetAt
            try? await store.markFiveHourResetNotified(
                profileID: profileID,
                resetAt: previousNotifiedResetAt
            )
            showError(error)
        }
    }

    private func confirmNotificationSwitch(title: String, body: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: text("switch_anyway"))
        alert.addButton(withTitle: text("cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func retryActiveIdentityConfirmation() {
        Task { await confirmActiveIdentity() }
    }

    private func confirmActiveIdentity() async {
        guard let activeID = activeAccountID,
              let profile = accounts.first(where: { $0.id == activeID })
        else {
            activeIdentityState = .confirmed
            return
        }
        activeIdentityState = .checking
        do {
            let activeHome = await store.activeCodexHome()
            let identity = try await operationGate.run { [codex] in
                try await codex.readIdentity(profileHome: activeHome)
            }
            activeIdentityState = identity.matches(profile) ? .confirmed : .mismatch
        } catch {
            activeIdentityState = .unavailable
        }
    }

    private func showError(_ error: any Error) {
        visibleError = OperationError(
            stage: nil,
            titleKey: "operation_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }

    private static func localDayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct LocalizedAppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
