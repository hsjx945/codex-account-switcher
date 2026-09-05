import CryptoKit
import Foundation
import Testing
@testable import CodexAccountSwitcher

struct SwitchCoordinatorTests {
    @Test func successfulSwitchCommitsVerifiedTargetAndClearsRecoveryState() async throws {
        let fixture = SwitchFixture()
        try await fixture.coordinator.switchAccount(to: fixture.target.id)
        #expect(await fixture.recorder.snapshot() == SwitchStage.allCases)
        #expect(await fixture.store.credentialOwner() == fixture.target.id)
        #expect(await fixture.store.activeAccountID() == fixture.target.id)
        #expect(await fixture.recovery.loadJournal() == nil)
    }

    @Test func verificationFailureRestoresExactOriginalCredentialAndDesktopState() async {
        let fixture = SwitchFixture(failure: .verifyTargetIdentity)
        await expectFailure(fixture, stage: .verifyTargetIdentity)
        #expect(await fixture.store.credentialOwner() == fixture.original.id)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.store.activeCredential() == fixture.originalCredential)
        #expect(await fixture.desktop.reopenCount() == 1)
        #expect(await fixture.recovery.loadJournal() == nil)
    }

    @Test func activationFailureAlsoUsesRollbackSnapshot() async {
        let fixture = SwitchFixture(failure: .activateTargetCredential)
        await expectFailure(fixture, stage: .activateTargetCredential)
        #expect(await fixture.store.activeCredential() == fixture.originalCredential)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.recovery.rollbackLoadCount() == 1)
    }

    @Test func reopenFailureLeavesCommittedJournalForStartupRetry() async {
        let fixture = SwitchFixture(failure: .reopenDesktop)
        await expectFailure(fixture, stage: .reopenDesktop)
        #expect(await fixture.store.activeAccountID() == fixture.target.id)
        #expect(await fixture.recovery.loadJournal()?.phase == .committed)
        await fixture.desktop.clearFailure()
        do {
            try await fixture.coordinator.recoverIfNeeded()
        } catch {
            Issue.record("Expected committed target recovery to succeed: \(error)")
        }
        #expect(await fixture.store.activeAccountID() == fixture.target.id)
        #expect(await fixture.recovery.loadJournal() == nil)
    }

    @Test func startupRecoveryRollsBackInterruptedActivation() async throws {
        let fixture = SwitchFixture()
        let journal = await fixture.recovery.prepare(
            originalCredential: fixture.originalCredential,
            originalAccountID: fixture.original.id,
            targetAccountID: fixture.target.id,
            desktopWasRunning: true
        )
        _ = await fixture.recovery.update(journal, phase: .targetActivated)
        await fixture.store.simulateInterruptedActivation()
        try await fixture.coordinator.recoverIfNeeded()
        #expect(await fixture.store.activeCredential() == fixture.originalCredential)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.recovery.loadJournal() == nil)
        #expect(await fixture.desktop.reopenCount() == 1)
    }

    @Test func encryptedRecoveryFileDoesNotContainCredentialPlaintext() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "switch-recovery-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SwitchRecoveryStore(baseURL: root, keyProvider: FixedRollbackKeyProvider())
        let secret = Data("credential-plaintext-must-not-appear".utf8)
        let journal = try await store.prepare(
            originalCredential: secret,
            originalAccountID: UUID(),
            targetAccountID: UUID(),
            desktopWasRunning: true
        )
        let sealedURL = root.appending(path: journal.backupFileName)
        let sealed = try Data(contentsOf: sealedURL)
        #expect(!sealed.contains(secret))
        #expect(try await store.loadOriginalCredential(for: journal) == secret)
        #expect(try permissions(sealedURL) == 0o600)
        #expect(try permissions(root.appending(path: "switch-journal.json")) == 0o600)
    }

    @Test func accountOperationGateDoesNotReenterAcrossAwait() async {
        let gate = AccountOperationGate()
        let probe = ConcurrencyProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try? await gate.run {
                        await probe.enter()
                        try? await Task.sleep(for: .milliseconds(20))
                        try Task.checkCancellation()
                        await probe.leave()
                    }
                }
            }
        }
        #expect(await probe.maximumConcurrency() == 1)
    }

    private func expectFailure(_ fixture: SwitchFixture, stage: SwitchStage) async {
        do {
            try await fixture.coordinator.switchAccount(to: fixture.target.id)
            Issue.record("Expected switch stage \(stage.rawValue) to fail")
        } catch let error as OperationError {
            #expect(error.stage == stage)
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private var maximum = 0
    func enter() {
        active += 1
        maximum = max(maximum, active)
    }
    func leave() { active -= 1 }
    func maximumConcurrency() -> Int { maximum }
}

struct FixedRollbackKeyProvider: RollbackKeyProviding {
    func loadOrCreateKey() throws -> SymmetricKey {
        SymmetricKey(data: Data(repeating: 0x5A, count: 32))
    }
}

private struct InjectedFailure: LocalizedError, Sendable {
    let stage: SwitchStage
    var errorDescription: String? { "Injected \(stage.rawValue) failure" }
}

private actor CallRecorder {
    private var values: [SwitchStage] = []
    func append(_ value: SwitchStage) { values.append(value) }
    func snapshot() -> [SwitchStage] { values }
}

private actor FakeDesktop: DesktopControlling {
    let recorder: CallRecorder
    private var failure: SwitchStage?
    private var opens = 0
    init(recorder: CallRecorder, failure: SwitchStage?) {
        self.recorder = recorder
        self.failure = failure
    }
    func isDesktopRunning() -> Bool { true }
    func closeDesktop() async throws {
        await recorder.append(.closeDesktop)
        if failure == .closeDesktop { throw InjectedFailure(stage: .closeDesktop) }
    }
    func reopenDesktop() async throws {
        await recorder.append(.reopenDesktop)
        if failure == .reopenDesktop { throw InjectedFailure(stage: .reopenDesktop) }
        opens += 1
    }
    func clearFailure() { failure = nil }
    func reopenCount() -> Int { opens }
}

private actor FakeStore: AccountStoring {
    let recorder: CallRecorder
    let original: AccountProfile
    let target: AccountProfile
    private let originalCredential: Data
    private let targetCredential: Data
    private let failure: SwitchStage?
    private var credential: Data
    private var credentialAccountID: UUID
    private var registryActiveID: UUID

    init(
        recorder: CallRecorder,
        failure: SwitchStage?,
        original: AccountProfile,
        target: AccountProfile,
        originalCredential: Data,
        targetCredential: Data
    ) {
        self.recorder = recorder
        self.failure = failure
        self.original = original
        self.target = target
        self.originalCredential = originalCredential
        self.targetCredential = targetCredential
        credential = originalCredential
        credentialAccountID = original.id
        registryActiveID = original.id
    }

    func loadRegistry() -> AccountRegistry {
        AccountRegistry(activeAccountID: registryActiveID, accounts: [original, target])
    }
    func profile(id: UUID) throws -> AccountProfile {
        guard id == original.id || id == target.id else { throw AccountStoreError.profileNotFound }
        return id == original.id ? original : target
    }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/\(id.uuidString)") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func readActiveCredential() -> Data { credential }
    func createProfileDirectory(id: UUID) -> URL { profileHome(id: id) }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() async throws {
        await recorder.append(.saveCurrentCredential)
        if failure == .saveCurrentCredential { throw InjectedFailure(stage: .saveCurrentCredential) }
    }
    func activateTargetCredential(id: UUID) async throws {
        await recorder.append(.activateTargetCredential)
        if failure == .activateTargetCredential { throw InjectedFailure(stage: .activateTargetCredential) }
        credential = targetCredential
        credentialAccountID = target.id
    }
    func restoreActiveCredential(id: UUID) {
        credential = originalCredential
        credentialAccountID = original.id
    }
    func restoreCredential(_ restored: Data) {
        credential = restored
        credentialAccountID = original.id
    }
    func commitActiveAccountID(_ id: UUID) async throws {
        await recorder.append(.commitActiveAccountID)
        if failure == .commitActiveAccountID { throw InjectedFailure(stage: .commitActiveAccountID) }
        registryActiveID = id
    }
    func credentialOwner() -> UUID { credentialAccountID }
    func activeAccountID() -> UUID { registryActiveID }
    func activeCredential() -> Data { credential }
    func simulateInterruptedActivation() {
        credential = targetCredential
        credentialAccountID = target.id
    }
}

private struct FakeCodex: CodexIdentityReading {
    let recorder: CallRecorder
    let failure: SwitchStage?
    let store: FakeStore
    let original: AccountProfile
    let target: AccountProfile
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        let activeID = await store.credentialOwner()
        if activeID == target.id {
            await recorder.append(.verifyTargetIdentity)
            if failure == .verifyTargetIdentity {
                throw InjectedFailure(stage: .verifyTargetIdentity)
            }
            return AccountIdentity(accountID: target.accountID, email: target.email)
        }
        return AccountIdentity(accountID: original.accountID, email: original.email)
    }
}

private actor FakeRecoveryStore: SwitchRecoveryPersisting {
    private var journal: SwitchJournal?
    private var originalCredential: Data?
    private var loads = 0
    func prepare(
        originalCredential: Data,
        originalAccountID: UUID,
        targetAccountID: UUID,
        desktopWasRunning: Bool
    ) -> SwitchJournal {
        let value = SwitchJournal(
            transactionID: UUID(), originalAccountID: originalAccountID,
            targetAccountID: targetAccountID, desktopWasRunning: desktopWasRunning,
            backupFileName: "memory", createdAt: Date(), phase: .prepared
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
        loads += 1
        guard let originalCredential else { throw SwitchRecoveryError.encryptedBackupMissing }
        return originalCredential
    }
    func clear(_ journal: SwitchJournal) {
        self.journal = nil
        originalCredential = nil
    }
    func rollbackLoadCount() -> Int { loads }
}

private struct SwitchFixture {
    let recorder = CallRecorder()
    let original: AccountProfile
    let target: AccountProfile
    let originalCredential = Data("original-auth".utf8)
    let targetCredential = Data("target-auth".utf8)
    let store: FakeStore
    let desktop: FakeDesktop
    let recovery = FakeRecoveryStore()
    let coordinator: SwitchCoordinator
    init(failure: SwitchStage? = nil) {
        let original = AccountProfile(
            id: UUID(), displayName: "Original", email: "original@example.com",
            accountID: "original-id", createdAt: Date(), lastUsedAt: nil
        )
        let target = AccountProfile(
            id: UUID(), displayName: "Target", email: "target@example.com",
            accountID: "target-id", createdAt: Date(), lastUsedAt: nil
        )
        self.original = original
        self.target = target
        let store = FakeStore(
            recorder: recorder, failure: failure, original: original, target: target,
            originalCredential: originalCredential, targetCredential: targetCredential
        )
        self.store = store
        let desktop = FakeDesktop(recorder: recorder, failure: failure)
        self.desktop = desktop
        coordinator = SwitchCoordinator(
            desktop: desktop,
            store: store,
            codex: FakeCodex(
                recorder: recorder, failure: failure, store: store,
                original: original, target: target
            ),
            recovery: recovery,
            operationGate: AccountOperationGate()
        )
    }
}
