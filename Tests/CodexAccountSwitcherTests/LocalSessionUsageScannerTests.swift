import Foundation
import Testing
@testable import CodexAccountSwitcher

struct LocalSessionUsageScannerTests {
    @Test func attributesCumulativeDeltasToTheCurrentModelWithoutCountingRepeats() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "local-model-usage-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions/2026/09/04", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-09-04T01:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-09-04T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-09-04T01:01:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-09-04T01:02:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}"#,
            #"{"timestamp":"2026-09-04T01:03:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160}}}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(
            to: sessions.appending(path: "rollout-fixture.jsonl")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z"))

        let summary = await LocalSessionUsageScanner(codexHome: root).scan(
            now: now,
            calendar: calendar
        )

        #expect(summary.models == [
            LocalModelTokenUsage(
                model: "gpt-5.6-sol",
                todayTokens: 100,
                sevenDayTokens: 100,
                thirtyDayTokens: 100
            ),
            LocalModelTokenUsage(
                model: "gpt-5.6-luna",
                todayTokens: 60,
                sevenDayTokens: 60,
                thirtyDayTokens: 60
            ),
        ])
    }
}
