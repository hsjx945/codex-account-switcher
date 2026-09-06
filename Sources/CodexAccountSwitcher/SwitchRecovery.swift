import CryptoKit
import Foundation
import Security
import Darwin

enum SwitchJournalPhase: String, Codable, Sendable {
    case prepared
    case desktopClosed
    case originalSaved
    case targetActivated
    case targetVerified
    case committed
    case rollingBack
    case rolledBack
}

struct SwitchJournal: Codable, Equatable, Sendable {
    let transactionID: UUID
    let originalAccountID: UUID
    let targetAccountID: UUID
    let desktopWasRunning: Bool
    let backupFileName: String
    let createdAt: Date
    var phase: SwitchJournalPhase
    var keyStorage: String? = nil
}

enum SwitchRecoveryError: LocalizedError, Sendable {
    case invalidKeychainItem
    case keychainFailure(OSStatus)
    case invalidJournal
    case unsafeLocalKey
    case encryptedBackupMissing
    case encryptedBackupInvalid

    var errorDescription: String? {
        switch self {
        case .invalidKeychainItem:
            "The rollback encryption key is invalid."
        case let .keychainFailure(status):
            "The rollback encryption key could not be accessed (Keychain status \(status))."
        case .unsafeLocalKey:
            "The local recovery key is missing, invalid, or has unsafe permissions. No credentials were changed."
        case .invalidJournal:
            "The switch recovery journal contains an invalid backup reference."
        case .encryptedBackupMissing:
            "The encrypted rollback credential is missing."
        case .encryptedBackupInvalid:
            "The encrypted rollback credential could not be decrypted."
        }
    }
}

protocol RollbackKeyProviding: Sendable {
    func loadOrCreateKey() throws -> SymmetricKey
}

struct KeychainRollbackKeyProvider: RollbackKeyProviding {
    var createsIfMissing = true
    private let service = "com.liuzhao.codex-account-switcher.rollback-key"
    private let account = "credential-backup"

    func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else {
                throw SwitchRecoveryError.invalidKeychainItem
            }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound, createsIfMissing else {
            throw SwitchRecoveryError.keychainFailure(status)
        }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw SwitchRecoveryError.keychainFailure(randomStatus)
        }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SwitchRecoveryError.keychainFailure(addStatus)
        }
        return SymmetricKey(data: bytes)
    }
}

/// User-private local storage, matching the app's existing credential-file boundary.
/// Does not read, change, or grant access to the legacy Keychain item.
struct LocalRollbackKeyProvider: RollbackKeyProviding {
    let directory: URL
    var createsIfMissing = true

    func loadOrCreateKey() throws -> SymmetricKey {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0 else {
            throw SwitchRecoveryError.unsafeLocalKey
        }
        let path = directory.appending(path: "rollback-key-v2.bin").path
        var descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT, createsIfMissing {
            let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            let created = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            if created >= 0 {
                defer { Darwin.close(created) }
                try bytes.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let count = Darwin.write(created, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                        if count < 0, errno == EINTR { continue }
                        guard count > 0 else { throw SwitchRecoveryError.unsafeLocalKey }
                        offset += count
                    }
                }
                guard fsync(created) == 0 else { throw SwitchRecoveryError.unsafeLocalKey }
            } else if errno != EEXIST {
                throw SwitchRecoveryError.unsafeLocalKey
            }
            descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw SwitchRecoveryError.unsafeLocalKey }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_nlink == 1, info.st_size == 32 else {
            throw SwitchRecoveryError.unsafeLocalKey
        }
        var bytes = Data(count: 32)
        try bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw SwitchRecoveryError.unsafeLocalKey }
                offset += count
            }
        }
        return SymmetricKey(data: bytes)
    }
}

protocol SwitchRecoveryPersisting: Sendable {
    func prepare(
        originalCredential: Data,
        originalAccountID: UUID,
        targetAccountID: UUID,
        desktopWasRunning: Bool
    ) async throws -> SwitchJournal
    func update(_ journal: SwitchJournal, phase: SwitchJournalPhase) async throws -> SwitchJournal
    func loadJournal() async throws -> SwitchJournal?
    func loadOriginalCredential(for journal: SwitchJournal) async throws -> Data
    func clear(_ journal: SwitchJournal) async throws
}

actor SwitchRecoveryStore: SwitchRecoveryPersisting {
    private let baseURL: URL
    private let fileManager: FileManager
    private let keyProvider: (any RollbackKeyProviding)?
    private var cachedKey: SymmetricKey?

    init(
        baseURL: URL? = nil,
        fileManager: FileManager = .default,
        keyProvider: (any RollbackKeyProviding)? = nil
    ) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseURL = support.appending(
                path: "Codex Account Switcher/recovery",
                directoryHint: .isDirectory
            )
        }
        self.fileManager = fileManager
        self.keyProvider = keyProvider
    }

    private func rollbackKey() throws -> SymmetricKey {
        guard let keyProvider else {
            return try LocalRollbackKeyProvider(directory: baseURL).loadOrCreateKey()
        }
        if let cachedKey { return cachedKey }
        let key = try keyProvider.loadOrCreateKey()
        cachedKey = key
        return key
    }

    private func recoveryKey(for journal: SwitchJournal) throws -> SymmetricKey {
        if journal.keyStorage == "local-v2" {
            return try LocalRollbackKeyProvider(directory: baseURL, createsIfMissing: false).loadOrCreateKey()
        }
        guard journal.keyStorage == nil else { throw SwitchRecoveryError.invalidJournal }
        // Old journals keep their original encryption key. Never substitute a new
        // local key if legacy authorization fails; keep the recovery files intact.
        if keyProvider != nil { return try rollbackKey() }
        return try KeychainRollbackKeyProvider(createsIfMissing: false).loadOrCreateKey()
    }

    private var journalURL: URL { baseURL.appending(path: "switch-journal.json") }

    func prepare(
        originalCredential: Data,
        originalAccountID: UUID,
        targetAccountID: UUID,
        desktopWasRunning: Bool
    ) throws -> SwitchJournal {
        try prepareDirectory()
        let transactionID = UUID()
        let backupFileName = "rollback-\(transactionID.uuidString).sealed"
        let backupURL = baseURL.appending(path: backupFileName)
        let key = try rollbackKey()
        let sealed = try AES.GCM.seal(originalCredential, using: key)
        guard let combined = sealed.combined else {
            throw SwitchRecoveryError.encryptedBackupInvalid
        }
        try secureWrite(combined, to: backupURL)

        let journal = SwitchJournal(
            transactionID: transactionID,
            originalAccountID: originalAccountID,
            targetAccountID: targetAccountID,
            desktopWasRunning: desktopWasRunning,
            backupFileName: backupFileName,
            createdAt: Date(),
            phase: .prepared,
            keyStorage: keyProvider == nil ? "local-v2" : nil
        )
        do {
            try writeJournal(journal)
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
        return journal
    }

    func update(_ journal: SwitchJournal, phase: SwitchJournalPhase) throws -> SwitchJournal {
        var updated = journal
        updated.phase = phase
        try writeJournal(updated)
        return updated
    }

    func loadJournal() throws -> SwitchJournal? {
        guard fileManager.fileExists(atPath: journalURL.path) else {
            try removeOrphanedBackups()
            return nil
        }
        return try Self.decoder.decode(SwitchJournal.self, from: Data(contentsOf: journalURL))
    }

    func loadOriginalCredential(for journal: SwitchJournal) throws -> Data {
        let url = try backupURL(for: journal.backupFileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SwitchRecoveryError.encryptedBackupMissing
        }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
            return try AES.GCM.open(box, using: recoveryKey(for: journal))
        } catch let error as SwitchRecoveryError {
            throw error
        } catch {
            throw SwitchRecoveryError.encryptedBackupInvalid
        }
    }

    func clear(_ journal: SwitchJournal) throws {
        let backupURL = try backupURL(for: journal.backupFileName)
        if journal.phase == .committed {
            // A committed transaction never reads the backup during startup
            // recovery. Delete it first so a failed cleanup keeps the journal
            // and can be retried without misreporting a reopen failure.
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            if fileManager.fileExists(atPath: journalURL.path) {
                try fileManager.removeItem(at: journalURL)
            }
        } else {
            // Earlier phases may still be interpreted as requiring rollback on
            // startup. Delete the journal first so a failed backup deletion
            // cannot leave a journal that references a missing backup.
            if fileManager.fileExists(atPath: journalURL.path) {
                try fileManager.removeItem(at: journalURL)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
    }

    private func writeJournal(_ journal: SwitchJournal) throws {
        try prepareDirectory()
        try secureWrite(Self.encoder.encode(journal), to: journalURL)
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func removeOrphanedBackups() throws {
        guard fileManager.fileExists(atPath: baseURL.path) else { return }
        for name in try fileManager.contentsOfDirectory(atPath: baseURL.path)
        where name.hasPrefix("rollback-") && name.hasSuffix(".sealed") {
            try fileManager.removeItem(at: baseURL.appending(path: name))
        }
    }

    private func backupURL(for fileName: String) throws -> URL {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.contains("/"),
              fileName.hasPrefix("rollback-"),
              fileName.hasSuffix(".sealed")
        else {
            throw SwitchRecoveryError.invalidJournal
        }
        return baseURL.appending(path: fileName)
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

actor AccountOperationGate {
    private struct Waiter: Sendable {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var isLocked = false
    private var waiters: [Waiter] = []

    func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !isLocked {
            isLocked = true
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        })
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().continuation.resume(returning: ())
    }
}
