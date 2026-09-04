import CryptoKit
import Foundation
import Security

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
}

enum SwitchRecoveryError: LocalizedError, Sendable {
    case invalidKeychainItem
    case keychainFailure(OSStatus)
    case invalidJournal
    case encryptedBackupMissing
    case encryptedBackupInvalid

    var errorDescription: String? {
        switch self {
        case .invalidKeychainItem:
            "The rollback encryption key is invalid."
        case let .keychainFailure(status):
            "The rollback encryption key could not be accessed (Keychain status \(status))."
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
    private let service = "com.liuzhao.codex-account-switcher.rollback-key"
    private let account = "credential-backup"

    func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else {
                throw SwitchRecoveryError.invalidKeychainItem
            }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
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
    private let keyProvider: any RollbackKeyProviding

    init(
        baseURL: URL? = nil,
        fileManager: FileManager = .default,
        keyProvider: any RollbackKeyProviding = KeychainRollbackKeyProvider()
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
        let key = try keyProvider.loadOrCreateKey()
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
            phase: .prepared
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
            return try AES.GCM.open(box, using: keyProvider.loadOrCreateKey())
        } catch let error as SwitchRecoveryError {
            throw error
        } catch {
            throw SwitchRecoveryError.encryptedBackupInvalid
        }
    }

    func clear(_ journal: SwitchJournal) throws {
        let backupURL = try backupURL(for: journal.backupFileName)
        if fileManager.fileExists(atPath: journalURL.path) {
            try fileManager.removeItem(at: journalURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
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
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}
