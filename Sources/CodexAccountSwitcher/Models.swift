import Foundation

struct AccountProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var nickname: String? = nil
    let email: String?
    let accountID: String?
    var planType: String? = nil
    let createdAt: Date
    var lastUsedAt: Date?

    var initials: String {
        let source = nickname?.nilIfBlank ?? email ?? displayName
        let parts = source
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    var subscriptionBadge: String? {
        switch planType?.lowercased() {
        case "plus": "PLUS"
        case "pro": "PRO"
        case "prolite": "PRO LITE"
        default: nil
        }
    }

    func primaryLabel(style: AccountNameStyle) -> String {
        switch style {
        case .email:
            email ?? nickname?.nilIfBlank ?? displayName
        case .nickname:
            nickname?.nilIfBlank ?? email ?? displayName
        case .nicknameAndEmail:
            nickname?.nilIfBlank ?? email ?? displayName
        }
    }

    func secondaryLabel(style: AccountNameStyle) -> String? {
        guard style == .nicknameAndEmail,
              nickname?.nilIfBlank != nil,
              let email,
              email.caseInsensitiveCompare(primaryLabel(style: style)) != .orderedSame
        else { return nil }
        return email
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct AccountRegistry: Codable, Equatable, Sendable {
    var activeAccountID: UUID?
    var accounts: [AccountProfile]

    static let empty = AccountRegistry(activeAccountID: nil, accounts: [])
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }
}

enum AccountNameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case email
    case nickname
    case nicknameAndEmail

    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable, Sendable {
    var language: AppLanguage
    var showsMenuBarPercentage: Bool
    var showsFiveHourUsage: Bool
    var accountNameStyle: AccountNameStyle
    var showsTokenActivity: Bool
    var automaticWarmupEnabled: Bool
    var warmupHour: Int
    var warmupMinute: Int
    var fiveHourResetNotificationsEnabled: Bool

    static let `default` = AppSettings(
        language: .system,
        showsMenuBarPercentage: true,
        showsFiveHourUsage: false,
        accountNameStyle: .email,
        showsTokenActivity: true,
        automaticWarmupEnabled: false,
        warmupHour: 8,
        warmupMinute: 30,
        fiveHourResetNotificationsEnabled: false
    )

    init(
        language: AppLanguage,
        showsMenuBarPercentage: Bool = true,
        showsFiveHourUsage: Bool = false,
        accountNameStyle: AccountNameStyle = .email,
        showsTokenActivity: Bool = true,
        automaticWarmupEnabled: Bool = false,
        warmupHour: Int = 8,
        warmupMinute: Int = 30,
        fiveHourResetNotificationsEnabled: Bool = false
    ) {
        self.language = language
        self.showsMenuBarPercentage = showsMenuBarPercentage
        self.showsFiveHourUsage = showsFiveHourUsage
        self.accountNameStyle = accountNameStyle
        self.showsTokenActivity = showsTokenActivity
        self.automaticWarmupEnabled = automaticWarmupEnabled
        self.warmupHour = min(max(warmupHour, 0), 23)
        self.warmupMinute = min(max(warmupMinute, 0), 59)
        self.fiveHourResetNotificationsEnabled = fiveHourResetNotificationsEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showsMenuBarPercentage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsMenuBarPercentage
        ) ?? true
        showsFiveHourUsage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsFiveHourUsage
        ) ?? false
        accountNameStyle = try container.decodeIfPresent(
            AccountNameStyle.self,
            forKey: .accountNameStyle
        ) ?? .email
        showsTokenActivity = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsTokenActivity
        ) ?? true
        automaticWarmupEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticWarmupEnabled
        ) ?? false
        warmupHour = min(max(try container.decodeIfPresent(Int.self, forKey: .warmupHour) ?? 8, 0), 23)
        warmupMinute = min(max(try container.decodeIfPresent(Int.self, forKey: .warmupMinute) ?? 30, 0), 59)
        fiveHourResetNotificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .fiveHourResetNotificationsEnabled
        ) ?? false
    }
}

struct DailyTokenUsage: Codable, Equatable, Sendable {
    let startDate: String
    let tokens: Int
}

struct ModelTokenUsage: Codable, Equatable, Sendable, Identifiable {
    let model: String
    let tokens: Int

    var id: String { model }
}

struct TokenActivity: Codable, Equatable, Sendable {
    let dailyBuckets: [DailyTokenUsage]
    let modelBreakdown: [ModelTokenUsage]
    let localModelCoverageStartedAt: Date?

    func tokens(inLastDays days: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        else { return 0 }
        return dailyBuckets.reduce(into: 0) { total, bucket in
            let parts = bucket.startDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(
                    from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
                  ),
                  date >= start,
                  date <= today
            else { return }
            total += bucket.tokens
        }
    }
}

struct WeeklyUsage: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let resetsAt: Date
    let fiveHourRemainingPercent: Int?
    let fiveHourResetsAt: Date?

    init(
        remainingPercent: Int,
        resetsAt: Date,
        fiveHourRemainingPercent: Int? = nil,
        fiveHourResetsAt: Date? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourResetsAt = fiveHourResetsAt
    }
}

struct UsageCacheEntry: Codable, Equatable, Sendable {
    let profileID: UUID
    let usage: WeeklyUsage
    let fetchedAt: Date
    var tokenActivity: TokenActivity?
    var lastNotifiedFiveHourResetAt: Date?

    init(
        profileID: UUID,
        usage: WeeklyUsage,
        fetchedAt: Date,
        tokenActivity: TokenActivity? = nil,
        lastNotifiedFiveHourResetAt: Date? = nil
    ) {
        self.profileID = profileID
        self.usage = usage
        self.fetchedAt = fetchedAt
        self.tokenActivity = tokenActivity
        self.lastNotifiedFiveHourResetAt = lastNotifiedFiveHourResetAt
    }
}

enum DesktopTaskState: Equatable, Sendable {
    case idle
    case active(count: Int)
    case unknown
}

enum NotificationSwitchDisposition: Equatable, Sendable {
    case noAction
    case direct
    case confirmActive(count: Int)
    case confirmUnknown
    case operationInProgress
}

enum NotificationSwitchPolicy {
    static func disposition(
        targetID: UUID,
        activeID: UUID?,
        isMutating: Bool,
        taskState: DesktopTaskState
    ) -> NotificationSwitchDisposition {
        guard targetID != activeID else { return .noAction }
        guard !isMutating else { return .operationInProgress }
        switch taskState {
        case .idle:
            return .direct
        case let .active(count):
            return .confirmActive(count: max(count, 1))
        case .unknown:
            return .confirmUnknown
        }
    }
}

enum DesktopTaskSafetyPolicy {
    static func effectiveState(
        desktopIsRunning: Bool,
        independentlyObservedState: DesktopTaskState?
    ) -> DesktopTaskState {
        guard desktopIsRunning else { return .idle }
        if case let .active(count)? = independentlyObservedState {
            return .active(count: max(count, 1))
        }
        return .unknown
    }
}

enum FiveHourResetDetector {
    static func resetToNotify(
        previousUsage: WeeklyUsage?,
        currentUsage: WeeklyUsage,
        lastNotifiedResetAt: Date?,
        now: Date
    ) -> Date? {
        guard let previousResetAt = previousUsage?.fiveHourResetsAt,
              let currentResetAt = currentUsage.fiveHourResetsAt,
              previousResetAt <= now,
              currentResetAt > previousResetAt,
              lastNotifiedResetAt.map({ $0 >= previousResetAt }) != true
        else { return nil }
        return previousResetAt
    }
}

struct UsageCache: Codable, Equatable, Sendable {
    var entries: [UsageCacheEntry]

    static let empty = UsageCache(entries: [])
}

enum WarmupOutcome: String, Codable, Equatable, Sendable {
    case attempting
    case confirmed
    case unconfirmed
    case failed
}

struct WarmupRecord: Codable, Equatable, Sendable {
    let attemptedAt: Date
    let outcome: WarmupOutcome
    let model: String?
}

struct WarmupHistory: Codable, Equatable, Sendable {
    var lastAttemptDayByProfile: [String: String]
    var lastRecordByProfile: [String: WarmupRecord]

    static let empty = WarmupHistory(lastAttemptDayByProfile: [:], lastRecordByProfile: [:])

    init(
        lastAttemptDayByProfile: [String: String],
        lastRecordByProfile: [String: WarmupRecord] = [:]
    ) {
        self.lastAttemptDayByProfile = lastAttemptDayByProfile
        self.lastRecordByProfile = lastRecordByProfile
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastAttemptDayByProfile = try container.decodeIfPresent(
            [String: String].self,
            forKey: .lastAttemptDayByProfile
        ) ?? [:]
        lastRecordByProfile = try container.decodeIfPresent(
            [String: WarmupRecord].self,
            forKey: .lastRecordByProfile
        ) ?? [:]
    }
}

enum UsageViewState: Equatable, Sendable {
    case idle
    case loaded(WeeklyUsage)
    case stale(WeeklyUsage, String)
    case unavailable(String)

    var displayedUsage: WeeklyUsage? {
        switch self {
        case let .loaded(usage), let .stale(usage, _):
            usage
        case .idle, .unavailable:
            nil
        }
    }

    var refreshError: String? {
        guard case let .stale(_, message) = self else { return nil }
        return message
    }
}

struct AccountIdentity: Equatable, Sendable {
    let accountID: String?
    let email: String?
    var planType: String? = nil

    var suggestedDisplayName: String {
        guard let email, let localPart = email.split(separator: "@").first else {
            return "Codex Account"
        }
        return String(localPart)
    }

    func matches(_ profile: AccountProfile) -> Bool {
        if let expected = profile.accountID, let actual = accountID {
            return expected == actual
        }
        if let expected = profile.email, let actual = email {
            return expected.caseInsensitiveCompare(actual) == .orderedSame
        }
        return false
    }
}

enum BeijingDateTimeFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

enum SwitchStage: String, CaseIterable, Sendable {
    case closeDesktop
    case saveCurrentCredential
    case activateTargetCredential
    case verifyTargetIdentity
    case commitActiveAccountID
    case reopenDesktop
}

struct OperationError: LocalizedError, Equatable, Sendable {
    let stage: SwitchStage?
    let titleKey: String
    let messageKey: String?
    let message: String
    let underlyingDescription: String?

    var errorDescription: String? {
        let title = L10n.string(titleKey, language: .english)
        if let stage {
            return "\(title) (\(stage.rawValue)): \(message)"
        }
        return "\(title): \(message)"
    }

    static func stage(_ stage: SwitchStage, _ error: any Error) -> OperationError {
        OperationError(
            stage: stage,
            titleKey: "switch_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }
}

enum AccountStoreError: LocalizedError, Equatable, Sendable {
    case profileNotFound
    case activeProfileMissing
    case activeCredentialMissing
    case targetCredentialMissing
    case cannotRemoveActiveAccount

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            "The account profile could not be found."
        case .activeProfileMissing:
            "No active account profile is configured."
        case .activeCredentialMissing:
            "The active Codex auth.json file is missing."
        case .targetCredentialMissing:
            "The selected account has no saved auth.json file."
        case .cannotRemoveActiveAccount:
            "The active account cannot be removed."
        }
    }
}

enum CodexClientError: LocalizedError, Equatable, Sendable {
    case executableNotFound
    case processLaunchFailed(String)
    case malformedResponse
    case remoteError(code: Int?, message: String)
    case connectionClosed
    case timeout
    case identityUnavailable
    case weeklyUsageUnavailable
    case tokenActivityUnavailable
    case loginFailed(String)
    case warmupFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "The Codex executable could not be found."
        case let .processLaunchFailed(message):
            "Codex app-server failed to start: \(message)"
        case .malformedResponse:
            "Codex app-server returned malformed JSON."
        case let .remoteError(code, message):
            code.map { "Codex app-server error \($0): \(message)" } ?? "Codex app-server error: \(message)"
        case .connectionClosed:
            "Codex app-server closed the connection."
        case .timeout:
            "Codex app-server did not respond before the timeout."
        case .identityUnavailable:
            "Codex did not return an account identity."
        case .weeklyUsageUnavailable:
            "No weekly Codex Usage window is available."
        case .tokenActivityUnavailable:
            "No daily Codex token activity is available."
        case let .loginFailed(message):
            "Codex login failed: \(message)"
        case let .warmupFailed(message):
            "Codex warmup failed: \(message)"
        }
    }
}
