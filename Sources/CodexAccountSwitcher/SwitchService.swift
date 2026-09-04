import Foundation

protocol DesktopControlling: Sendable {
    func isDesktopRunning() async -> Bool
    func closeDesktop() async throws
    func reopenDesktop() async throws
}

protocol CodexIdentityReading: Sendable {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity
}

protocol SwitchServicing: Sendable {
    func switchAccount(to targetID: UUID) async throws
    func recoverIfNeeded() async throws
}

actor SwitchCoordinator: SwitchServicing {
    let desktop: any DesktopControlling
    let store: any AccountStoring
    let codex: any CodexIdentityReading
    let recovery: any SwitchRecoveryPersisting
    let operationGate: AccountOperationGate

    init(
        desktop: any DesktopControlling,
        store: any AccountStoring,
        codex: any CodexIdentityReading,
        recovery: any SwitchRecoveryPersisting,
        operationGate: AccountOperationGate
    ) {
        self.desktop = desktop
        self.store = store
        self.codex = codex
        self.recovery = recovery
        self.operationGate = operationGate
    }

    func switchAccount(to targetID: UUID) async throws {
        try await operationGate.run { [self] in
            try await performSwitch(to: targetID)
        }
    }

    func recoverIfNeeded() async throws {
        try await operationGate.run { [self] in
            guard let journal = try await recovery.loadJournal() else { return }
            try await recover(journal)
        }
    }

    private func performSwitch(to targetID: UUID) async throws {
        if let interrupted = try await recovery.loadJournal() {
            try await recover(interrupted)
        }
        let target: AccountProfile
        let originalActiveID: UUID
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            let registry = try await store.loadRegistry()
            guard let activeID = registry.activeAccountID,
                  registry.accounts.contains(where: { $0.id == activeID }) else {
                throw AccountStoreError.activeProfileMissing
            }
            originalActiveID = activeID
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        let desktopWasRunning = await desktop.isDesktopRunning()
        let originalCredential: Data
        do {
            originalCredential = try await store.readActiveCredential()
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }
        var journal: SwitchJournal
        do {
            journal = try await recovery.prepare(
                originalCredential: originalCredential,
                originalAccountID: originalActiveID,
                targetAccountID: targetID,
                desktopWasRunning: desktopWasRunning
            )
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        do {
            if desktopWasRunning { try await desktop.closeDesktop() }
            journal = try await recovery.update(journal, phase: .desktopClosed)
        } catch {
            throw await rollbackError(
                journal: journal,
                failedStage: .closeDesktop,
                originalError: error
            )
        }

        do {
            try await store.saveCurrentCredential()
            journal = try await recovery.update(journal, phase: .originalSaved)
        } catch {
            throw await rollbackError(
                journal: journal,
                failedStage: .saveCurrentCredential,
                originalError: error
            )
        }

        do {
            try await store.activateTargetCredential(id: targetID)
            journal = try await recovery.update(journal, phase: .targetActivated)
        } catch {
            throw await rollbackError(
                journal: journal,
                failedStage: .activateTargetCredential,
                originalError: error
            )
        }

        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
            journal = try await recovery.update(journal, phase: .targetVerified)
        } catch {
            throw await rollbackError(
                journal: journal,
                failedStage: .verifyTargetIdentity,
                originalError: error
            )
        }

        do {
            try await store.commitActiveAccountID(targetID)
            journal = try await recovery.update(journal, phase: .committed)
        } catch {
            throw await rollbackError(
                journal: journal,
                failedStage: .commitActiveAccountID,
                originalError: error
            )
        }

        do {
            if desktopWasRunning { try await desktop.reopenDesktop() }
            try await recovery.clear(journal)
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func rollbackError(
        journal: SwitchJournal,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        do {
            try await rollback(journal)
            return OperationError.stage(failedStage, originalError)
        } catch let restorationError {
            return OperationError(
                stage: failedStage,
                titleKey: "switch_failed",
                messageKey: nil,
                message: """
                \(originalError.localizedDescription) Restoring the previous credential also failed: \
                \(restorationError.localizedDescription)
                """,
                underlyingDescription: """
                \(String(describing: originalError)); restoration: \
                \(String(describing: restorationError))
                """
            )
        }
    }

    private func rollback(_ journal: SwitchJournal) async throws {
        var updated = try await recovery.update(journal, phase: .rollingBack)
        let credential = try await recovery.loadOriginalCredential(for: updated)
        try await store.restoreCredential(credential)
        try await store.commitActiveAccountID(updated.originalAccountID)
        let original = try await store.profile(id: updated.originalAccountID)
        let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
        guard identity.matches(original) else {
            throw CodexClientError.identityUnavailable
        }
        updated = try await recovery.update(updated, phase: .rolledBack)
        if updated.desktopWasRunning { try await desktop.reopenDesktop() }
        try await recovery.clear(updated)
    }

    private func recover(_ journal: SwitchJournal) async throws {
        guard journal.phase == .committed else {
            try await rollback(journal)
            return
        }
        let target = try await store.profile(id: journal.targetAccountID)
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
        } catch {
            try await rollback(journal)
            return
        }
        if journal.desktopWasRunning { try await desktop.reopenDesktop() }
        try await recovery.clear(journal)
    }
}
