import Darwin
import Foundation
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct SwitchLatencyTests {
    @Test func switchPreemptsStalledBackgroundQueriesWithoutDiscardingCachedUsage() async throws {
        let fixture = try LatencyFixture()
        defer { fixture.remove() }
        let store = AccountStore(baseURL: fixture.root.appending(path: "store"), activeHomeURL: fixture.root.appending(path: "active"))
        var profiles: [AccountProfile] = []
        for index in 0..<3 {
            let profile = AccountProfile(id: UUID(), displayName: "Fixture \(index)", email: nil, accountID: "fixture", createdAt: Date())
            let home = try await store.createProfileDirectory(id: profile.id)
            try Data("synthetic".utf8).write(to: home.appending(path: "auth.json"))
            try await store.addProfile(profile)
            try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 75, resetsAt: nil), profileID: profile.id)
            profiles.append(profile)
        }
        let gate = AccountOperationGate()
        let service = LatencySwitch(store: store, gate: gate, fixture: fixture)
        let model = AppModel(store: store, codex: fixture.client, switchService: service, operationGate: gate)
        await model.start()
        model.refreshWeeklyUsage()
        try await fixture.waitForRequest()
        let started = ContinuousClock.now
        await model.switchAccount(to: profiles[1].id)
        let elapsed = started.duration(to: .now)
        print("SWITCH_HANDOFF_SECONDS=\(elapsed)")
        #expect(elapsed < .seconds(2))
        #expect(model.activeAccountID == profiles[1].id)
        #expect(!model.isMutating)
        #expect(model.visibleError == nil)
        // Cancelled reads must not mark the retained quota as an error.
        for profile in profiles {
            if case .loaded = model.usageStates[profile.id] {} else {
                Issue.record("Cancelled refresh changed cached usage to failure")
            }
        }
        // The switch fixture releases the stall; the interrupted refresh resumes.
        await model.waitForWeeklyUsageRefresh()
        #expect(model.tokenRefreshPending.isEmpty)
        #expect(model.tokenRefreshErrors.isEmpty)
    }

    @Test func cancellingRPCStopsChildAndReturnsBeforeRequestTimeout() async throws {
        let fixture = try LatencyFixture()
        defer { fixture.remove() }
        let task = Task { try await fixture.client.readWeeklyUsage(profileHome: fixture.root) }
        try await fixture.waitForRequest()
        let pidText = try String(contentsOf: fixture.root.appending(path: "request-pid"), encoding: .utf8)
        let pid = try #require(Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        let started = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled query must throw")
        } catch is CancellationError {} catch {
            Issue.record("Expected cancellation, got \(error)")
        }
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(Darwin.kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

private struct LatencySwitch: SwitchServicing {
    let store: AccountStore
    let gate: AccountOperationGate
    let fixture: LatencyFixture

    func recoverIfNeeded() async throws {}
    func switchAccount(to targetID: UUID) async throws {
        try await gate.run {
            let text = try String(contentsOf: fixture.root.appending(path: "request-pid"), encoding: .utf8)
            let pid = try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            #expect(Darwin.kill(pid, 0) == -1, "Background child must exit before switching credentials")
            try Data().write(to: fixture.root.appending(path: "release"))
            try await store.commitActiveAccountID(targetID)
        }
    }
}

private struct LatencyFixture: Sendable {
    let root: URL
    let executable: URL
    var client: CodexClient {
        CodexClient(locator: CodexExecutableLocator(explicitURL: executable), requestTimeout: .seconds(3))
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "switch-latency-\(UUID())")
        executable = root.appending(path: "fake-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Replace the shell with a TERM-ignoring sleeper, without grandchildren,
        // to exercise bounded cleanup of an unresponsive RPC child.
        let script = #"""
        #!/bin/sh
        fixture_dir=$(dirname "$0")
        trap '' TERM
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              if test ! -f "$fixture_dir/release"; then
                printf '%s\n' "$$" > "$fixture_dir/request-pid"
                exec /bin/sleep 30
              else
                printf '%s\n' '{"id":1,"result":{"rateLimits":{"secondary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1900000000}}}}'
              fi ;;
            *usage*) printf '%s\n' '{"id":1,"result":{"dailyUsageBuckets":[]}}' ;;
            *account*) printf '%s\n' '{"id":1,"result":{"account":{"accountId":"fixture"}}}' ;;
          esac
        done
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func waitForRequest() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: root.appending(path: "request-pid").path) {
            guard ContinuousClock.now < deadline else { throw CodexClientError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
