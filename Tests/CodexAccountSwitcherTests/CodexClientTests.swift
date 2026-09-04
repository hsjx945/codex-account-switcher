import Foundation
import Testing
@testable import CodexAccountSwitcher

struct CodexClientTests {
    @Test func performsHandshakeBeforeReadingFiveHourAndWeeklyUsage() async throws {
        let fixture = try ScriptFixture(body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*)
              test "$state" -eq 1 || exit 11
              state=2
              ;;
            *initialize*)
              state=1
              printf '%s\n' '{"id":0,"result":{}}'
              ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 12
              printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        let usage = try await client.readWeeklyUsage(profileHome: fixture.root)
        #expect(usage.remainingPercent == 42)
        #expect(usage.resetsAt == Date(timeIntervalSince1970: 1_750_000_000))
        #expect(usage.fiveHourRemainingPercent == 20)
        #expect(usage.fiveHourResetsAt == Date(timeIntervalSince1970: 100))
    }

    @Test func decodesAccountIdentity() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        let identity = try await client.readIdentity(profileHome: fixture.root)
        #expect(identity == AccountIdentity(accountID: "acct-123", email: "user@example.com"))
    }

    @Test func readsOfficialDailyTokenBuckets() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *usage*read*) printf '%s\n' '{"id":1,"result":{"summary":{"lifetimeTokens":9000},"dailyUsageBuckets":[{"startDate":"2026-09-03","tokens":1200},{"startDate":"2026-09-04","tokens":2300}]}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        let activity = try await client.readTokenActivity(profileHome: fixture.root)

        #expect(activity.dailyBuckets == [
            DailyTokenUsage(startDate: "2026-09-03", tokens: 1200),
            DailyTokenUsage(startDate: "2026-09-04", tokens: 2300),
        ])
    }

    @Test func reportsActiveDesktopTasksFromOfficialThreadStatus() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *thread*list*) printf '%s\n' '{"id":1,"result":{"data":[{"status":{"type":"active","activeFlags":["waitingOnTool"]}},{"status":{"type":"idle"}}],"nextCursor":null}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        #expect(try await client.readDesktopTaskState(profileHome: fixture.root) == .active(count: 1))
    }

    @Test func reportsIdleOnlyAfterACompleteThreadList() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *thread*list*) printf '%s\n' '{"id":1,"result":{"data":[{"status":{"type":"idle"}},{"status":{"type":"notLoaded"}}],"nextCursor":null}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        #expect(try await client.readDesktopTaskState(profileHome: fixture.root) == .unknown)
    }

    @Test func failsClosedForUnknownThreadStatus() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *thread*list*) printf '%s\n' '{"id":1,"result":{"data":[{"status":{"type":"systemError"}}],"nextCursor":null}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        #expect(try await client.readDesktopTaskState(profileHome: fixture.root) == .unknown)
    }

    @Test func doesNotTurnUnavailableDailyBucketsIntoZeroUsage() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *usage*read*) printf '%s\n' '{"id":1,"result":{"dailyUsageBuckets":null}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        do {
            _ = try await client.readTokenActivity(profileHome: fixture.root)
            Issue.record("Null daily buckets should be unavailable")
        } catch let error as CodexClientError {
            #expect(error == .tokenActivityUnavailable)
        }
    }

    @Test func warmupDiscoversAndUsesTheSmallAvailableModel() async throws {
        let fixture = try ScriptFixture(body: """
        if test "${1:-}" = "exec"; then
          case " $* " in
            *" --model gpt-5.6-luna "*) exit 0 ;;
            *) exit 21 ;;
          esac
        fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-sol"},{"model":"gpt-5.6-luna"}]}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        #expect(try await client.warmup(profileHome: fixture.root) == "gpt-5.6-luna")
    }

    @Test func warmupDoesNotFallBackToAnUnverifiedLargeModel() async throws {
        let fixture = try ScriptFixture(body: """
        if test "${1:-}" = "exec"; then exit 31; fi
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *model*list*) printf '%s\n' '{"id":1,"result":{"data":[{"model":"gpt-5.6-sol"}]}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        do {
            _ = try await client.warmup(profileHome: fixture.root)
            Issue.record("Warmup should skip when no verified small model is available")
        } catch let error as CodexClientError {
            #expect(error == .warmupFailed("No verified small model is available."))
        }
    }

    @Test func surfacesMalformedJSON() async {
        let fixture = try! ScriptFixture(body: """
        while IFS= read -r line; do
          printf '%s\n' 'malformed'
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("Malformed JSON should fail")
        } catch let error as CodexClientError {
            #expect(error == .malformedResponse)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }
    }

    @Test func timesOutWithoutRetrying() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*) sleep 5 ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .milliseconds(50)
        )

        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("The request should time out")
        } catch let error as CodexClientError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }
    }
}

private struct ScriptFixture {
    let root: URL
    let executable: URL

    init(body: String) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "codex-client-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        executable = root.appending(path: "fake-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
