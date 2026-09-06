import CryptoKit
import Foundation
import Testing
@testable import CodexAccountSwitcher

struct LocalRollbackKeyTests {
    @Test func localRecoverySurvivesRestartWithoutKeychain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "local-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Data("synthetic-credential-only".utf8)
        let store = SwitchRecoveryStore(baseURL: root)
        let journal = try await store.prepare(originalCredential: fixture, originalAccountID: UUID(), targetAccountID: UUID(), desktopWasRunning: false)
        #expect(journal.keyStorage == "local-v2")
        let restarted = SwitchRecoveryStore(baseURL: root)
        let recoveredJournal = try #require(await restarted.loadJournal())
        #expect(try await restarted.loadOriginalCredential(for: recoveredJournal) == fixture)
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appending(path: "rollback-key-v2.bin").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(!Data(try Data(contentsOf: root.appending(path: journal.backupFileName))).contains(fixture))
        try await restarted.clear(recoveredJournal)
        let again = try await restarted.prepare(originalCredential: fixture, originalAccountID: UUID(), targetAccountID: UUID(), desktopWasRunning: false)
        #expect(try await SwitchRecoveryStore(baseURL: root).loadOriginalCredential(for: again) == fixture)
    }

    @Test func missingRecoveryKeyDoesNotGetReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "missing-local-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SwitchRecoveryStore(baseURL: root)
        let journal = try await store.prepare(originalCredential: Data("synthetic".utf8), originalAccountID: UUID(), targetAccountID: UUID(), desktopWasRunning: false)
        let key = root.appending(path: "rollback-key-v2.bin")
        try FileManager.default.removeItem(at: key)
        do {
            _ = try await SwitchRecoveryStore(baseURL: root).loadOriginalCredential(for: journal)
            Issue.record("missing key must fail without replacing it")
        } catch {}
        #expect(!FileManager.default.fileExists(atPath: key.path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: journal.backupFileName).path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "switch-journal.json").path))
    }

    @Test func refusesSymlinkAndPublicKeyPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "unsafe-local-key-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = LocalRollbackKeyProvider(directory: root)
        _ = try provider.loadOrCreateKey()
        let key = root.appending(path: "rollback-key-v2.bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: key.path)
        #expect(throws: (any Error).self) { try provider.loadOrCreateKey() }
        let original = root.appending(path: "original-key")
        try FileManager.default.moveItem(at: key, to: original)
        try FileManager.default.createSymbolicLink(at: key, withDestinationURL: original)
        #expect(throws: (any Error).self) { try provider.loadOrCreateKey() }
    }

    @Test func legacyJournalDecodesWithoutChangingItsKeyFormat() throws {
        let id = UUID()
        let raw = """
        {"transactionID":"\(id)","originalAccountID":"\(id)","targetAccountID":"\(id)","desktopWasRunning":false,"backupFileName":"rollback-test.sealed","createdAt":0,"phase":"prepared"}
        """
        #expect(try JSONDecoder().decode(SwitchJournal.self, from: Data(raw.utf8)).keyStorage == nil)
    }
}
