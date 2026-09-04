import Foundation
import ServiceManagement
import SwiftUI

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage, TokenActivity?)
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

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [AccountProfile] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var usageStates: [UUID: UsageViewState] = [:]
    @Published private(set) var tokenActivities: [UUID: TokenActivity] = [:]
    @Published private(set) var localModelUsage: LocalModelUsageSummary?
    @Published private(set) var warmupStatuses: [UUID: WarmupRecord] = [:]
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var isMutating = false
    @Published private(set) var isAddingAccount = false
    @Published var visibleError: OperationError?
    @Published private(set) var activeIdentityConfirmed = true
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled

    private let store: AccountStore
    private let codex: CodexClient
    private let switchService: any SwitchServicing
    private let operationGate: AccountOperationGate
    private let localSessionScanner: LocalSessionUsageScanner
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false

    init(
        store: AccountStore,
        codex: CodexClient,
        switchService: any SwitchServicing,
        operationGate: AccountOperationGate,
        localSessionScanner: LocalSessionUsageScanner = .init()
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
        self.operationGate = operationGate
        self.localSessionScanner = localSessionScanner
    }

    static func live() -> AppModel {
        let store = AccountStore()
        let codex = CodexClient()
        let operationGate = AccountOperationGate()
        let recovery = SwitchRecoveryStore()
        return AppModel(
            store: store,
            codex: codex,
            switchService: SwitchCoordinator(
                desktop: DesktopController(),
                store: store,
                codex: codex,
                recovery: recovery,
                operationGate: operationGate
            ),
            operationGate: operationGate
        )
    }

    func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    var activeRemainingPercent: Int? {
        guard let activeAccountID else { return nil }
        return usageStates[activeAccountID]?.displayedUsage?.remainingPercent
    }

    var displayedAccounts: [AccountProfile] {
        accounts.sorted { lhs, rhs in
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
        guard !hasStarted else { return }
        hasStarted = true
        refreshLaunchAtLoginStatus()
        do {
            try await switchService.recoverIfNeeded()
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
        } catch {
            showError(error)
        }
    }

    func refreshWeeklyUsage() {
        if isBackgroundUsageRefreshEnabled {
            scheduleNextWeeklyUsageRefresh()
        }
        guard !accounts.isEmpty, usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
        }
    }

    func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    func startBackgroundUsageRefresh(every interval: Duration = .seconds(300)) async {
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        await start()
        refreshWeeklyUsage()
    }

    func stopBackgroundUsageRefresh() {
        isBackgroundUsageRefreshEnabled = false
        nextUsageRefreshTask?.cancel()
        nextUsageRefreshTask = nil
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
                            let usage = try await codex.readWeeklyUsage(profileHome: home)
                            let tokens = try? await codex.readTokenActivity(profileHome: home)
                            return (usage, tokens)
                        }
                        return .success(id, values.0, values.1)
                    } catch {
                        return .failure(id, error.localizedDescription)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .success(id, usage, activity):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    usageStates[id] = .loaded(usage)
                    do {
                        try await store.cacheWeeklyUsage(usage, profileID: id)
                        if let activity {
                            tokenActivities[id] = activity
                            try await store.cacheTokenActivity(activity, profileID: id)
                        }
                    } catch {
                        showError(error)
                    }
                case let .failure(id, message):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    if let cached = usageStates[id]?.displayedUsage {
                        usageStates[id] = .stale(cached, message)
                    } else {
                        usageStates[id] = .unavailable(message)
                    }
                }
            }
        }
        if settings.showsTokenActivity {
            localModelUsage = await localSessionScanner.scan()
        }
        await performScheduledWarmupIfNeeded()
    }

    private func performScheduledWarmupIfNeeded(now: Date = Date()) async {
        guard settings.automaticWarmupEnabled else { return }
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
            guard history.lastAttemptDayByProfile[account.id.uuidString] != day else { continue }
            guard case let .loaded(currentUsage) = usageStates[account.id],
                  currentUsage.fiveHourResetsAt == nil || currentUsage.fiveHourResetsAt! <= now
            else { continue }

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
                showError(error)
            }
        }
    }

    func switchAccount(to id: UUID) async {
        guard id != activeAccountID, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await switchService.switchAccount(to: id)
            apply(try await store.loadRegistry())
            activeIdentityConfirmed = true
        } catch let error as OperationError {
            if error.stage == .reopenDesktop {
                do {
                    apply(try await store.loadRegistry())
                    activeIdentityConfirmed = true
                } catch {
                    showError(error)
                    return
                }
                visibleError = OperationError(
                    stage: .reopenDesktop,
                    titleKey: "switched_reopen_title",
                    messageKey: "switched_reopen_message",
                    message: text("switched_reopen_message"),
                    underlyingDescription: error.underlyingDescription
                )
            } else {
                visibleError = error
            }
        } catch {
            showError(error)
        }
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
        do {
            let id = UUID()
            let home = try await store.createProfileDirectory(id: id)
            try Task.checkCancellation()
            let identity = try await operationGate.run { [codex] in
                try await codex.login(profileHome: home)
            }
            try Task.checkCancellation()
            let profile = AccountProfile(
                id: id,
                displayName: identity.email ?? identity.suggestedDisplayName,
                email: identity.email,
                accountID: identity.accountID,
                createdAt: Date(),
                lastUsedAt: nil
            )
            try await operationGate.run { [store] in
                try await store.addProfile(profile)
            }
            apply(try await store.loadRegistry())
        } catch is CancellationError {
            return
        } catch {
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
        } catch {
            showError(error)
        }
    }

    func updateNickname(id: UUID, nickname: String?) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await store.updateNickname(id: id, nickname: nickname)
            apply(try await store.loadRegistry())
        } catch {
            showError(error)
        }
    }

    func setLanguage(_ language: AppLanguage) async {
        settings.language = language
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    func setShowsMenuBarPercentage(_ enabled: Bool) async {
        settings.showsMenuBarPercentage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    func setShowsFiveHourUsage(_ enabled: Bool) async {
        settings.showsFiveHourUsage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    func setAccountNameStyle(_ style: AccountNameStyle) async {
        settings.accountNameStyle = style
        await persistSettings()
    }

    func setShowsTokenActivity(_ enabled: Bool) async {
        settings.showsTokenActivity = enabled
        await persistSettings()
        if enabled { refreshWeeklyUsage() }
    }

    func setAutomaticWarmupEnabled(_ enabled: Bool) async {
        settings.automaticWarmupEnabled = enabled
        await persistSettings()
        if enabled { refreshWeeklyUsage() }
    }

    func setWarmupTime(_ date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        settings.warmupHour = components.hour ?? 8
        settings.warmupMinute = components.minute ?? 30
        await persistSettings()
    }

    var warmupTime: Date {
        Calendar.current.date(
            bySettingHour: settings.warmupHour,
            minute: settings.warmupMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func persistSettings() async {
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
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
        tokenActivities = tokenActivities.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        warmupStatuses = warmupStatuses.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            usageStates[entry.profileID] = .loaded(entry.usage)
            if let activity = entry.tokenActivity {
                tokenActivities[entry.profileID] = activity
            }
        }
    }

    private func confirmActiveIdentity() async {
        guard let activeID = activeAccountID,
              let profile = accounts.first(where: { $0.id == activeID })
        else { return }
        do {
            let activeHome = await store.activeCodexHome()
            let identity = try await operationGate.run { [codex] in
                try await codex.readIdentity(profileHome: activeHome)
            }
            activeIdentityConfirmed = identity.matches(profile)
        } catch {
            activeIdentityConfirmed = false
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
