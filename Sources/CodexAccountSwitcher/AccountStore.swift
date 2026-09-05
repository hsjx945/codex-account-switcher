import Foundation
import Darwin

struct AccountRemovalError: LocalizedError, Equatable, Sendable {
    let deletionErrorDescription: String
    let registryRestorationErrorDescription: String

    init(deletionError: any Error, registryRestorationError: any Error) {
        deletionErrorDescription = deletionError.localizedDescription
        registryRestorationErrorDescription = registryRestorationError.localizedDescription
    }

    var errorDescription: String? {
        "The account credential could not be removed (\(deletionErrorDescription)). "
            + "Restoring the account registry also failed (\(registryRestorationErrorDescription))."
    }
}

protocol AccountStoring: Sendable {
    func loadRegistry() async throws -> AccountRegistry
    func profile(id: UUID) async throws -> AccountProfile
    func profileHome(id: UUID) async -> URL
    func activeCodexHome() async -> URL
    func activeCredentialExists() async -> Bool
    func readActiveCredential() async throws -> Data
    func createProfileDirectory(id: UUID) async throws -> URL
    func importCurrentProfile(_ profile: AccountProfile) async throws
    func addProfile(_ profile: AccountProfile) async throws
    func removeAccount(id: UUID) async throws
    func saveCurrentCredential() async throws
    func activateTargetCredential(id: UUID) async throws
    func restoreActiveCredential(id: UUID) async throws
    func restoreCredential(_ credential: Data) async throws
    func commitActiveAccountID(_ id: UUID) async throws
}

actor AccountStore: AccountStoring {
    let baseURL: URL
    let activeHomeURL: URL

    private let fileManager: FileManager
    private let legacyBaseURL: URL?
    private var registry: AccountRegistry?
    private var usageCache: UsageCache?

    init(
        baseURL: URL? = nil,
        legacyBaseURL: URL? = nil,
        activeHomeURL: URL? = nil,
        fileManager: sending FileManager = .default
    ) {
        self.fileManager = fileManager
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        if let baseURL {
            self.baseURL = baseURL
            self.legacyBaseURL = legacyBaseURL
        } else {
            self.baseURL = applicationSupportURL.appending(
                path: "Codex Account Switcher",
                directoryHint: .isDirectory
            )
            self.legacyBaseURL = applicationSupportURL.appending(
                path: "Codex Account Switcher Lite",
                directoryHint: .isDirectory
            )
        }
        self.activeHomeURL = activeHomeURL
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    private var accountsURL: URL { baseURL.appending(path: "accounts.json") }
    private var settingsURL: URL { baseURL.appending(path: "settings.json") }
    private var usageCacheURL: URL { baseURL.appending(path: "usage-cache.json") }
    private var warmupHistoryURL: URL { baseURL.appending(path: "warmup-history.json") }
    private var profilesURL: URL { baseURL.appending(path: "accounts", directoryHint: .isDirectory) }

    func loadRegistry() throws -> AccountRegistry {
        try prepareDirectories()
        if let registry { return registry }
        guard fileManager.fileExists(atPath: accountsURL.path) else {
            registry = .empty
            return .empty
        }
        let loaded = try Self.decoder.decode(AccountRegistry.self, from: Data(contentsOf: accountsURL))
        registry = loaded
        return loaded
    }

    func loadSettings() throws -> AppSettings {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: settingsURL.path) else { return .default }
        return try Self.decoder.decode(AppSettings.self, from: Data(contentsOf: settingsURL))
    }

    func saveSettings(_ settings: AppSettings) throws {
        try prepareDirectories()
        try writeJSON(settings, to: settingsURL)
    }

    func loadWarmupHistory() throws -> WarmupHistory {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: warmupHistoryURL.path) else { return .empty }
        return try Self.decoder.decode(WarmupHistory.self, from: Data(contentsOf: warmupHistoryURL))
    }

    func recordWarmupAttempt(profileID: UUID, day: String, attemptedAt: Date = Date()) throws {
        var history = try loadWarmupHistory()
        history.lastAttemptDayByProfile[profileID.uuidString] = day
        history.lastRecordByProfile[profileID.uuidString] = WarmupRecord(
            attemptedAt: attemptedAt,
            outcome: .attempting,
            model: nil
        )
        try writeJSON(history, to: warmupHistoryURL)
    }

    func recordWarmupResult(profileID: UUID, record: WarmupRecord) throws {
        var history = try loadWarmupHistory()
        history.lastRecordByProfile[profileID.uuidString] = record
        try writeJSON(history, to: warmupHistoryURL)
    }

    func loadUsageCache() throws -> UsageCache {
        try prepareDirectories()
        if let usageCache { return usageCache }
        guard fileManager.fileExists(atPath: usageCacheURL.path) else {
            usageCache = .empty
            return .empty
        }
        let loaded = try Self.decoder.decode(UsageCache.self, from: Data(contentsOf: usageCacheURL))
        usageCache = loaded
        return loaded
    }

    func cacheWeeklyUsage(_ usage: WeeklyUsage, profileID: UUID, fetchedAt: Date = Date()) throws {
        let registry = try loadRegistry()
        guard registry.accounts.contains(where: { $0.id == profileID }) else { return }
        var cache = try loadUsageCache()
        let existing = cache.entries.first(where: { $0.profileID == profileID })
        let entry = UsageCacheEntry(
            profileID: profileID,
            usage: usage,
            fetchedAt: fetchedAt,
            tokenActivity: existing?.tokenActivity,
            tokenFetchedAt: existing?.tokenFetchedAt,
            lastNotifiedFiveHourResetAt: existing?.lastNotifiedFiveHourResetAt
        )
        if let index = cache.entries.firstIndex(where: { $0.profileID == profileID }) {
            cache.entries[index] = entry
        } else {
            cache.entries.append(entry)
        }
        try saveUsageCache(cache)
    }

    func markFiveHourResetNotified(profileID: UUID, resetAt: Date?) throws {
        var cache = try loadUsageCache()
        guard let index = cache.entries.firstIndex(where: { $0.profileID == profileID }) else { return }
        cache.entries[index].lastNotifiedFiveHourResetAt = resetAt
        try saveUsageCache(cache)
    }

    func cacheTokenActivity(
        _ activity: TokenActivity,
        profileID: UUID,
        fetchedAt: Date = Date()
    ) throws {
        let registry = try loadRegistry()
        guard registry.accounts.contains(where: { $0.id == profileID }) else { return }
        var cache = try loadUsageCache()
        if let index = cache.entries.firstIndex(where: { $0.profileID == profileID }) {
            cache.entries[index].tokenActivity = activity
            cache.entries[index].tokenFetchedAt = fetchedAt
        } else {
            return
        }
        try saveUsageCache(cache)
    }

    func profile(id: UUID) throws -> AccountProfile {
        let registry = try loadRegistry()
        guard let profile = registry.accounts.first(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        return profile
    }

    func profileHome(id: UUID) -> URL {
        profilesURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func activeCodexHome() -> URL { activeHomeURL }

    func activeCredentialExists() -> Bool {
        fileManager.fileExists(atPath: activeHomeURL.appending(path: "auth.json").path)
    }

    func readActiveCredential() throws -> Data {
        let source = activeHomeURL.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.activeCredentialMissing
        }
        return try Data(contentsOf: source)
    }

    func createProfileDirectory(id: UUID) throws -> URL {
        try prepareDirectories()
        let directory = profileHome(id: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    func importCurrentProfile(_ profile: AccountProfile) throws {
        let source = activeHomeURL.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.activeCredentialMissing
        }
        _ = try createProfileDirectory(id: profile.id)
        try copyCredential(from: source, to: profileHome(id: profile.id).appending(path: "auth.json"))

        var current = try loadRegistry()
        current.accounts.append(profile)
        current.activeAccountID = profile.id
        try saveRegistry(current)
    }

    func addProfile(_ profile: AccountProfile) throws {
        let authURL = profileHome(id: profile.id).appending(path: "auth.json")
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw AccountStoreError.targetCredentialMissing
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
        var current = try loadRegistry()
        if current.accounts.isEmpty, current.activeAccountID == nil, activeCredentialExists() {
            throw AccountStoreError.activeProfileMissing
        }
        let shouldBecomeActive = current.accounts.isEmpty
            && current.activeAccountID == nil
            && !activeCredentialExists()
        if shouldBecomeActive {
            // The first browser login establishes the active credential before the
            // registry advertises the profile as active. This keeps an empty
            // registry and an empty active CODEX_HOME consistent on every path.
            let bytes = try Data(contentsOf: authURL)
            try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
            try secureAtomicWrite(bytes, to: activeHomeURL.appending(path: "auth.json"))
        }
        current.accounts.append(profile)
        if shouldBecomeActive {
            current.activeAccountID = profile.id
            current.accounts[current.accounts.count - 1].lastUsedAt = Date()
        }
        do {
            try saveRegistry(current)
        } catch {
            // A failed registry write must not leave a newly installed first
            // credential pointing at an unregistered profile.
            if shouldBecomeActive {
                let activeAuthURL = activeHomeURL.appending(path: "auth.json")
                try? fileManager.removeItem(at: activeAuthURL)
            }
            throw error
        }
    }

    func removeUnregisteredProfile(id: UUID) throws {
        let current = try loadRegistry()
        guard !current.accounts.contains(where: { $0.id == id }) else { return }
        let directory = profileHome(id: id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func updateNickname(id: UUID, nickname: String?) throws {
        var current = try loadRegistry()
        guard let index = current.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        let normalized = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        current.accounts[index].nickname = normalized?.isEmpty == false ? normalized : nil
        try saveRegistry(current)
    }

    func updatePlanType(id: UUID, planType: String) throws {
        var current = try loadRegistry()
        guard let index = current.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        guard current.accounts[index].planType != planType else { return }
        current.accounts[index].planType = planType
        try saveRegistry(current)
    }

    func removeAccount(id: UUID) throws {
        var current = try loadRegistry()
        guard current.activeAccountID != id else {
            throw AccountStoreError.cannotRemoveActiveAccount
        }
        guard current.accounts.contains(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        let original = current
        current.accounts.removeAll(where: { $0.id == id })
        try saveRegistry(current)

        do {
            try fileManager.removeItem(at: profileHome(id: id))
        } catch let deletionError {
            // Keep the credential recoverable whenever physical deletion fails.
            // If restoring the registry fails too, surface both failures while
            // leaving the credential on disk as recoverable evidence.
            do {
                try saveRegistry(original)
            } catch let registryRestorationError {
                throw AccountRemovalError(
                    deletionError: deletionError,
                    registryRestorationError: registryRestorationError
                )
            }
            throw deletionError
        }

        // These records are derived metadata. Once registry removal and
        // credential deletion have both committed, stale entries are harmless
        // and filtered by profile ID on load, so cleanup must not turn a
        // successful account removal into a reported failure.
        if var cache = try? loadUsageCache() {
            cache.entries.removeAll(where: { $0.profileID == id })
            try? saveUsageCache(cache)
        }
        if var warmupHistory = try? loadWarmupHistory() {
            warmupHistory.lastAttemptDayByProfile.removeValue(forKey: id.uuidString)
            warmupHistory.lastRecordByProfile.removeValue(forKey: id.uuidString)
            try? writeJSON(warmupHistory, to: warmupHistoryURL)
        }
    }

    func saveCurrentCredential() throws {
        let current = try loadRegistry()
        guard let activeID = current.activeAccountID else {
            throw AccountStoreError.activeProfileMissing
        }
        guard current.accounts.contains(where: { $0.id == activeID }) else {
            throw AccountStoreError.activeProfileMissing
        }
        let source = activeHomeURL.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.activeCredentialMissing
        }
        try copyCredential(from: source, to: profileHome(id: activeID).appending(path: "auth.json"))
    }

    func activateTargetCredential(id: UUID) throws {
        try installCredential(id: id)
    }

    func restoreActiveCredential(id: UUID) throws {
        try installCredential(id: id)
    }

    func restoreCredential(_ credential: Data) throws {
        try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
        try secureAtomicWrite(credential, to: activeHomeURL.appending(path: "auth.json"))
    }

    private func installCredential(id: UUID) throws {
        _ = try profile(id: id)
        let source = profileHome(id: id).appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.targetCredentialMissing
        }

        try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
        let destination = activeHomeURL.appending(path: "auth.json")
        let bytes = try Data(contentsOf: source)
        try secureAtomicWrite(bytes, to: destination)
    }

    func commitActiveAccountID(_ id: UUID) throws {
        var current = try loadRegistry()
        guard let index = current.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        current.activeAccountID = id
        current.accounts[index].lastUsedAt = Date()
        try saveRegistry(current)
    }

    private func saveRegistry(_ value: AccountRegistry) throws {
        try writeJSON(value, to: accountsURL)
        registry = value
    }

    private func saveUsageCache(_ value: UsageCache) throws {
        try writeJSON(value, to: usageCacheURL)
        usageCache = value
    }

    private func prepareDirectories() throws {
        if !fileManager.fileExists(atPath: baseURL.path),
           let legacyBaseURL,
           fileManager.fileExists(atPath: legacyBaseURL.path) {
            try fileManager.moveItem(at: legacyBaseURL, to: baseURL)
        }
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
        try fileManager.createDirectory(at: profilesURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profilesURL.path)
    }

    private func copyCredential(from source: URL, to destination: URL) throws {
        let bytes = try Data(contentsOf: source)
        try secureAtomicWrite(bytes, to: destination)
    }

    private func secureAtomicWrite(_ bytes: Data, to destination: URL) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appending(path: "\(destination.lastPathComponent).switcher-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }

        do {
            try bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < rawBuffer.count {
                    let count = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        rawBuffer.count - offset
                    )
                    guard count > 0 else { throw currentPOSIXError() }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
            guard Darwin.close(descriptor) == 0 else { throw currentPOSIXError() }
        } catch {
            _ = Darwin.close(descriptor)
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        if Darwin.rename(temporary.path, destination.path) != 0 {
            let error = currentPOSIXError()
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func writeJSON<T: Encodable>(_ value: T, to destination: URL) throws {
        let bytes = try Self.encoder.encode(value)
        try secureAtomicWrite(bytes, to: destination)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
