import CryptoKit
import Darwin
import Foundation
import Testing
@testable import CodexAccountSwitcher

struct FocusedReliabilityTests {
    @Test func rejectsUnsafeJSONIntegerConversions() throws {
        let oversized = try JSONDecoder().decode(JSONValue.self, from: Data("1e300".utf8))
        #expect(oversized.intValue == nil)
        #expect(JSONValue.number(.infinity).intValue == nil)
        #expect(JSONValue.number(.nan).intValue == nil)
        #expect(JSONValue.number(1.5).intValue == nil)
        #expect(JSONValue.number(42).intValue == 42)
    }

    @Test func rejectsBlankAccountIdentityValues() async throws {
        let fixture = try ReliabilityScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"accountId":"  ","email":" "}}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("Blank identity fields should fail closed")
        } catch let error as CodexClientError {
            #expect(error == .identityUnavailable)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }
    }

    @Test func warmupTimeoutKillsSIGTERMIgnoringProcessWithinBound() async throws {
        let fixture = try ReliabilityScriptFixture(body: """
        if test "${1:-}" = "exec"; then
          trap '' TERM
          while :; do :; done
        fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-luna"}]}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .milliseconds(150)
        )
        let startedAt = ContinuousClock.now

        do {
            _ = try await client.warmup(profileHome: fixture.root)
            Issue.record("Warmup should time out")
        } catch let error as CodexClientError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }

        let elapsed = ContinuousClock.now - startedAt
        #expect(elapsed < .seconds(2))
    }

    @Test func cancelledQueuedGateOperationNeverRunsAndDoesNotStickGate() async throws {
        let gate = AccountOperationGate()
        let probe = ReliabilityProbe()
        let holder = Task {
            try await gate.run {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
            }
        }
        await Task.yield()

        let queued = Task {
            do {
                try await gate.run {
                    await probe.recordExecution()
                    try Task.checkCancellation()
                }
            } catch {
                // Cancellation is the expected result for the queued task.
            }
        }
        for _ in 0..<20 { await Task.yield() }
        queued.cancel()
        _ = await holder.result
        _ = await queued.result

        #expect(await probe.executionCount() == 0)
        try await gate.run {
            try Task.checkCancellation()
        }
    }

    @Test func committedCleanupFailureIsReportedSeparatelyAndRetainsJournal() async throws {
        let original = ReliabilityProfile(
            id: UUID(), displayName: "Original", email: "original@example.com", accountID: "original"
        )
        let target = ReliabilityProfile(
            id: UUID(), displayName: "Target", email: "target@example.com", accountID: "target"
        )
        let store = ReliabilitySwitchStore(original: original.profile, target: target.profile)
        let desktop = ReliabilityDesktop()
        let recovery = ReliabilityRecovery(failClear: true)
        let coordinator = SwitchCoordinator(
            desktop: desktop,
            store: store,
            codex: ReliabilityCodex(target: target.profile),
            recovery: recovery,
            operationGate: AccountOperationGate()
        )

        do {
            try await coordinator.switchAccount(to: target.id)
            Issue.record("Cleanup failure should be surfaced")
        } catch let error as OperationError {
            #expect(error.stage == nil)
            #expect(error.message.localizedCaseInsensitiveContains("cleanup"))
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }

        #expect(await store.activeAccountID() == target.id)
        #expect(await desktop.reopenCount() == 1)
        #expect(await recovery.loadJournal()?.phase == .committed)
    }

    @Test func removalReportsBothDeletionAndRegistryRestoreFailures() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "account-removal-fault-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let support = root.appending(path: "support", directoryHint: .isDirectory)
        let activeHome = root.appending(path: "active", directoryHint: .isDirectory)
        let targetID = UUID()
        let targetHome = support.appending(path: "accounts", directoryHint: .isDirectory)
            .appending(path: targetID.uuidString, directoryHint: .isDirectory)
        let fileManager = RemovalFaultFileManager(targetURL: targetHome, supportURL: support)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.appending(path: "accounts").path)
            try? FileManager.default.removeItem(at: root)
        }

        try fileManager.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data("original-auth".utf8).write(to: activeHome.appending(path: "auth.json"))
        let store = AccountStore(baseURL: support, activeHomeURL: activeHome, fileManager: fileManager)
        let original = AccountProfile(
            id: UUID(), displayName: "Original", email: "original@example.com",
            accountID: "original", createdAt: Date(), lastUsedAt: nil
        )
        try await store.importCurrentProfile(original)
        let target = AccountProfile(
            id: targetID, displayName: "Target", email: "target@example.com",
            accountID: "target", createdAt: Date(), lastUsedAt: nil
        )
        _ = try await store.createProfileDirectory(id: target.id)
        try Data("target-auth".utf8).write(to: targetHome.appending(path: "auth.json"))
        try await store.addProfile(target)

        do {
            try await store.removeAccount(id: target.id)
            Issue.record("Removal fault should be surfaced")
        } catch let error as AccountRemovalError {
            #expect(!error.deletionErrorDescription.isEmpty)
            #expect(!error.registryRestorationErrorDescription.isEmpty)
            #expect(error.errorDescription?.localizedCaseInsensitiveContains("registry") == true)
        } catch {
            Issue.record("Expected AccountRemovalError, got \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: targetHome.appending(path: "auth.json").path))
        #expect(try Data(contentsOf: targetHome.appending(path: "auth.json")) == Data("target-auth".utf8))
    }
}

private actor ReliabilityProbe {
    private var executions = 0
    func recordExecution() { executions += 1 }
    func executionCount() -> Int { executions }
}

private struct ReliabilityScriptFixture {
    let root: URL
    let executable: URL

    init(body: String) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "codex-focused-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        executable = root.appending(path: "fake-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private struct ReliabilityProfile {
    let id: UUID
    let displayName: String
    let email: String
    let accountID: String

    var profile: AccountProfile {
        AccountProfile(
            id: id,
            displayName: displayName,
            email: email,
            accountID: accountID,
            createdAt: Date(),
            lastUsedAt: nil
        )
    }
}

private actor ReliabilitySwitchStore: AccountStoring {
    let original: AccountProfile
    let target: AccountProfile
    private var credential: Data
    private var activeID: UUID

    init(original: AccountProfile, target: AccountProfile) {
        self.original = original
        self.target = target
        credential = Data("original-auth".utf8)
        activeID = original.id
    }

    func loadRegistry() -> AccountRegistry {
        AccountRegistry(activeAccountID: activeID, accounts: [original, target])
    }
    func profile(id: UUID) throws -> AccountProfile {
        if id == original.id { return original }
        if id == target.id { return target }
        throw AccountStoreError.profileNotFound
    }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/\(id.uuidString)") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/reliability-active") }
    func activeCredentialExists() -> Bool { true }
    func readActiveCredential() -> Data { credential }
    func createProfileDirectory(id: UUID) -> URL { profileHome(id: id) }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() async throws {}
    func activateTargetCredential(id: UUID) async throws { credential = Data("target-auth".utf8) }
    func restoreActiveCredential(id: UUID) async throws { credential = Data("original-auth".utf8) }
    func restoreCredential(_ credential: Data) async throws { self.credential = credential }
    func commitActiveAccountID(_ id: UUID) async throws { activeID = id }
    func activeAccountID() -> UUID { activeID }
}

private struct ReliabilityCodex: CodexIdentityReading {
    let target: AccountProfile
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        AccountIdentity(accountID: target.accountID, email: target.email)
    }
}

private actor ReliabilityDesktop: DesktopControlling {
    private var opens = 0
    func isDesktopRunning() -> Bool { true }
    func closeDesktop() async throws {}
    func reopenDesktop() async throws { opens += 1 }
    func reopenCount() -> Int { opens }
}

private struct ReliabilityCleanupError: LocalizedError, Sendable {
    var errorDescription: String? { "injected cleanup failure" }
}

private actor ReliabilityRecovery: SwitchRecoveryPersisting {
    private let failClear: Bool
    private var journal: SwitchJournal?
    private var originalCredential: Data?

    init(failClear: Bool) { self.failClear = failClear }

    func prepare(
        originalCredential: Data,
        originalAccountID: UUID,
        targetAccountID: UUID,
        desktopWasRunning: Bool
    ) -> SwitchJournal {
        let value = SwitchJournal(
            transactionID: UUID(),
            originalAccountID: originalAccountID,
            targetAccountID: targetAccountID,
            desktopWasRunning: desktopWasRunning,
            backupFileName: "memory",
            createdAt: Date(),
            phase: .prepared
        )
        self.originalCredential = originalCredential
        journal = value
        return value
    }

    func update(_ journal: SwitchJournal, phase: SwitchJournalPhase) -> SwitchJournal {
        var updated = journal
        updated.phase = phase
        self.journal = updated
        return updated
    }

    func loadJournal() -> SwitchJournal? { journal }

    func loadOriginalCredential(for journal: SwitchJournal) throws -> Data {
        guard let originalCredential else { throw SwitchRecoveryError.encryptedBackupMissing }
        return originalCredential
    }

    func clear(_ journal: SwitchJournal) throws {
        if failClear { throw ReliabilityCleanupError() }
        self.journal = nil
        originalCredential = nil
    }
}

private final class RemovalFaultFileManager: FileManager, @unchecked Sendable {
    private let targetURL: URL
    private let supportURL: URL

    init(targetURL: URL, supportURL: URL) {
        self.targetURL = targetURL.standardizedFileURL
        self.supportURL = supportURL.standardizedFileURL
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == targetURL {
            try setAttributes([.posixPermissions: 0o500], ofItemAtPath: supportURL.path)
            throw POSIXError(.EACCES)
        }
        try super.removeItem(at: URL)
    }
}
