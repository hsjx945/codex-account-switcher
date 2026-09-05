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
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
        do {
            try await recovery.clear(journal)
        } catch {
            // The target and registry are already committed. Keep the
            // recovery journal for a later cleanup attempt and report the
            // cleanup failure separately from a Desktop reopen failure.
            throw OperationError(
                stage: nil,
                titleKey: "operation_failed",
                messageKey: nil,
                message: "The account switch committed successfully, but switch recovery cleanup failed: "
                    + "\(error.localizedDescription) It will be retried.",
                underlyingDescription: String(describing: error)
            )
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
        let target: AccountProfile
        do {
            target = try await store.profile(id: journal.targetAccountID)
        } catch {
            // A committed target is already the source of truth. A transient
            // registry read must not turn startup recovery into a rollback.
            throw OperationError.stage(.verifyTargetIdentity, error)
        }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
        } catch {
            // Keep the committed target and journal until a later startup can
            // verify it. Rolling back here could replace a valid target with
            // an older credential solely because account/read was unavailable.
            throw OperationError.stage(.verifyTargetIdentity, error)
        }
        do {
            if journal.desktopWasRunning { try await desktop.reopenDesktop() }
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
        do {
            try await recovery.clear(journal)
        } catch {
            // Cleanup is deliberately retried on the next startup; preserving
            // the journal is safer than claiming recovery completed. This is
            // not a Desktop reopen failure and must not be reported as one.
            throw OperationError(
                stage: nil,
                titleKey: "operation_failed",
                messageKey: nil,
                message: "The committed account is active, but switch recovery cleanup will be retried.",
                underlyingDescription: String(describing: error)
            )
        }
    }
}
