import Foundation
import Testing
@testable import CodexAccountSwitcher

struct LocalSessionUsageScannerTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!
    private var utc: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }

    @Test func incrementallyReadsAppendsWithoutRestartAndDoesNotRecountRefreshes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "live.jsonl")
        try fixture.append([meta("session-a"), legacy(at: "2026-09-04T01:00:00Z", total: 100)], to: file)
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 100)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 100)
        try fixture.append([legacy(at: "2026-09-04T02:00:00Z", total: 160)], to: file)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 160)
    }

    @Test func buffersHalfLinesRecoversTruncationAndFindsNewDateDirectories() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "partial.jsonl")
        try fixture.append([meta("session-a")], to: file)
        let half = legacy(at: "2026-09-04T01:00:00Z", total: 100)
        let split = half.index(half.startIndex, offsetBy: half.count / 2)
        try fixture.appendRaw(String(half[..<split]), to: file)
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 0)
        try fixture.appendRaw(String(half[split...]) + "\n", to: file)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 100)
        try Data((meta("session-a") + "\n" + legacy(at: "2026-09-04T03:00:00Z", total: 40) + "\n").utf8).write(to: file)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 40)
        let next = try fixture.file(day: "2026/09/05", name: "new-day.jsonl")
        try fixture.append([meta("session-b"), legacy(at: "2026-09-04T04:00:00Z", total: 7)], to: next)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 47)
    }

    @Test func distinguishesZeroFromUnavailableAndExcludesPreviousDay() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 0)
        let file = try fixture.file(day: "2026/09/03", name: "old.jsonl")
        try fixture.append([meta("old"), legacy(at: "2026-09-03T23:59:59Z", total: 9)], to: file)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 0)
        try FileManager.default.removeItem(at: fixture.root.appending(path: "sessions"))
        let unavailable = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
        #expect(unavailable.todayTokens == nil)
        if case .failed = unavailable.state {} else { Issue.record("missing roots must fail explicitly") }
    }

    @Test func modernRecordsOverrideLegacyAndResponseIDsDeduplicateAcrossFiles() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let first = try fixture.file(day: "2026/09/04", name: "modern.jsonl")
        try fixture.append([meta("modern"), modern(at: "2026-09-04T01:00:00Z", response: "r1", tokens: 40), legacy(at: "2026-09-04T01:00:01Z", total: 40)], to: first)
        let second = try fixture.file(day: "2026/09/04", name: "other.jsonl")
        try fixture.append([meta("other"), modern(at: "2026-09-04T01:00:00Z", response: "r1", tokens: 40), modern(at: "2026-09-04T02:00:00Z", response: "r2", tokens: 6)], to: second)
        #expect(await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc).todayTokens == 46)
    }

    @Test func mixedFormatKeepsLegacyBeforeModernAndSuppressesPairedCumulativeEvents() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "mixed.jsonl")
        try fixture.append([
            meta("mixed"),
            legacy(at: "2026-09-04T01:00:00Z", total: 100),
            modern(at: "2026-09-04T02:00:00Z", response: "mixed-r1", tokens: 10),
            legacy(at: "2026-09-04T02:00:01Z", total: 110),
        ], to: file)
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 110)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 110)
    }

    @Test func malformedOrStructurallyInvalidTargetEventsFailInsteadOfReportingZero() async throws {
        let cases = [
            #"{"type":"token_usage_record""#,
            #"{"timestamp":"2026-09-04T01:00:00Z","type":"token_usage_record"}"#,
            #"{"timestamp":"2026-09-04T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"bad"}}}}"#,
        ]
        for line in cases {
            let fixture = try Fixture(); defer { fixture.remove() }
            let file = try fixture.file(day: "2026/09/04", name: "invalid.jsonl")
            try fixture.append([line], to: file)
            let result = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
            #expect(result.todayTokens == nil)
            if case .failed = result.state {} else { Issue.record("invalid target event must fail") }
        }
    }

    @Test func explicitRateLimitOnlyTokenEventDoesNotTurnAnEmptyDayIntoUnknown() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "rate-limit.jsonl")
        try fixture.append([
            #"{"timestamp":"2026-09-04T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
        ], to: file)
        #expect(await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc).todayTokens == 0)
    }

    @Test func deduplicatesArchivedCopyAndForkedParentHistory() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let parent = try fixture.file(day: "2026/09/04", name: "parent.jsonl")
        let first = legacyDetailed(at: "2026-09-04T01:00:00Z", cumulative: (100, 80, 20, 20, 5), last: (100, 80, 20, 20, 5))
        let second = legacyDetailed(at: "2026-09-04T02:00:00Z", cumulative: (160, 130, 30, 30, 7), last: (60, 50, 10, 10, 2))
        let parentLines = [meta("parent"), first, second]
        try fixture.append(parentLines, to: parent)
        let archived = try fixture.file(day: "", name: "copy.jsonl", archived: true)
        try fixture.append(parentLines, to: archived)
        let child = try fixture.file(day: "2026/09/04", name: "child.jsonl")
        try fixture.append([meta("child", parent: "parent"), first, second, legacyDetailed(at: "2026-09-04T04:00:00Z", cumulative: (190, 155, 35, 35, 8), last: (30, 25, 5, 5, 1))], to: child)
        let actual = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc).todayTokens
        #expect(actual == 190)
    }

    @Test func invalidModernComponentsAreNotMistakenForMissingComponents() async throws {
        for usage in [
            #"{"total_tokens":120,"input_tokens":100,"cached_input_tokens":101,"output_tokens":20}"#,
            #"{"total_tokens":120,"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":21}"#,
            #"{"total_tokens":120,"input_tokens":100,"cached_input_tokens":-1,"output_tokens":20}"#,
            #"{"total_tokens":120,"input_tokens":100,"cached_input_tokens":true,"output_tokens":20}"#,
        ] {
            let fixture = try Fixture(); defer { fixture.remove() }
            let file = try fixture.file(day: "2026/09/04", name: "invalid-components.jsonl")
            try fixture.append(["{\"timestamp\":\"2026-09-04T01:00:00Z\",\"type\":\"token_usage_record\",\"payload\":{\"response_id\":\"bad\",\"usage\":\(usage)}}"], to: file)
            let result = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
            #expect(result.todayTokens == nil)
            if case .failed = result.state {} else { Issue.record("invalid components must fail explicitly") }
        }
    }

    @Test func modernBreakdownUsesMutuallyExclusivePartsAndOneDedupStreamForModels() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "breakdown.jsonl")
        try fixture.append([
            turnContext("context-model"),
            modernDetailed(at: "2026-09-04T01:00:00Z", response: "d1", input: 100, cached: 60, output: 20, reasoning: 5, model: "payload-model"),
            legacyDetailed(at: "2026-09-04T01:00:01Z", cumulative: (120, 100, 60, 20, 5), last: (120, 100, 60, 20, 5)),
        ], to: file)
        let result = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
        #expect(result.usage == LocalTokenComponents(total: 120, uncachedInput: 40, cachedInput: 60, output: 20))
        #expect(result.models == [LocalModelTokenUsage(model: "payload-model", usage: result.usage!)])
        #expect(result.models.map(\.usage.total).reduce(0, +) == result.todayTokens)
    }

    @Test func legacyUsesLastUsageAndSkipsRepeatedCumulativeTuple() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "legacy-last.jsonl")
        let first = legacyDetailed(at: "2026-09-04T01:00:00Z", cumulative: (100, 80, 20, 20, 5), last: (100, 80, 20, 20, 5))
        let repeated = legacyDetailed(at: "2026-09-04T01:00:01Z", cumulative: (100, 80, 20, 20, 5), last: (100, 80, 20, 20, 5))
        let changed = legacyDetailed(at: "2026-09-04T02:00:00Z", cumulative: (130, 105, 25, 25, 6), last: (30, 25, 5, 5, 1))
        try fixture.append([first, repeated, changed], to: file)
        let result = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
        #expect(result.todayTokens == 130)
        #expect(result.usage?.uncachedInput == 80)
        #expect(result.usage?.cachedInput == 25)
        #expect(result.usage?.output == 25)
    }

    @Test func choosesMostCompleteArchivedCopyAndDoesNotDropSingleMatchingIndependentSessions() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let active = try fixture.file(day: "2026/09/04", name: "active.jsonl")
        try fixture.append([meta("copied"), modern(at: "2026-09-04T01:00:00Z", response: "a", tokens: 10)], to: active)
        let archived = try fixture.file(day: "", name: "archived.jsonl", archived: true)
        try fixture.append([meta("copied"), modern(at: "2026-09-04T01:00:00Z", response: "a", tokens: 10), modern(at: "2026-09-04T02:00:00Z", response: "b", tokens: 5)], to: archived)
        for id in ["independent-1", "independent-2"] {
            let file = try fixture.file(day: "2026/09/04", name: "\(id).jsonl")
            try fixture.append([meta(id), legacyDetailed(at: "2026-09-04T03:00:00Z", cumulative: (20, 15, 5, 5, 1), last: (20, 15, 5, 5, 1))], to: file)
        }
        #expect(await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc).todayTokens == 55)
    }

    @Test func parentPrefixRequiresCompleteMatchingTotalAndLastTuple() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let parent = try fixture.file(day: "2026/09/04", name: "tuple-parent.jsonl")
        let parentEvent = legacyDetailed(at: "2026-09-04T01:00:00Z", cumulative: (100, 80, 20, 20, 5), last: (100, 80, 20, 20, 5))
        try fixture.append([meta("tuple-parent"), parentEvent], to: parent)
        let child = try fixture.file(day: "2026/09/04", name: "tuple-child.jsonl")
        let differentLast = legacyDetailed(at: "2026-09-04T02:00:00Z", cumulative: (100, 80, 20, 20, 5), last: (90, 70, 20, 20, 4))
        try fixture.append([meta("tuple-child", parent: "tuple-parent"), differentLast], to: child)
        #expect(await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc).todayTokens == 190)
    }

    @Test func missingModelAndMissingComponentsRemainExplicitlyUnknown() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let file = try fixture.file(day: "2026/09/04", name: "unknown.jsonl")
        try fixture.append([modern(at: "2026-09-04T01:00:00Z", response: "unknown-r", tokens: 9)], to: file)
        let result = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
        #expect(result.usage == LocalTokenComponents(total: 9, uncachedInput: nil, cachedInput: nil, output: nil))
        #expect(result.models == [LocalModelTokenUsage(model: nil, usage: result.usage!)])
    }

    @Test func conflictingDuplicateResponseAndSameLengthRewriteAreHandledSafely() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let first = try fixture.file(day: "2026/09/04", name: "conflict-a.jsonl")
        let second = try fixture.file(day: "2026/09/04", name: "conflict-b.jsonl")
        try fixture.append([modern(at: "2026-09-04T01:00:00Z", response: "same", tokens: 10)], to: first)
        try fixture.append([modern(at: "2026-09-04T01:00:00Z", response: "same", tokens: 11)], to: second)
        let conflict = await LocalSessionUsageScanner(codexHome: fixture.root).refresh(now: now, calendar: utc)
        #expect(conflict.todayTokens == nil)
        if case .failed = conflict.state {} else { Issue.record("conflicting response usage must fail") }

        try FileManager.default.removeItem(at: second)
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 10)
        let replacement = modern(at: "2026-09-04T01:00:00Z", response: "same", tokens: 20)
        let originalSize = try Data(contentsOf: first).count
        var bytes = Data((replacement + "\n").utf8)
        if bytes.count < originalSize { bytes.append(Data(repeating: 0x20, count: originalSize - bytes.count)) }
        if bytes.count > originalSize { bytes = bytes.prefix(originalSize) }
        try bytes.write(to: first)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: first.path)
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 20)
    }

    @Test func monitoringStopsAndNoHistoryIsNeverAssignedToAnAccount() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let scanner = LocalSessionUsageScanner(codexHome: fixture.root)
        await scanner.start(interval: .milliseconds(20)) { _ in }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await scanner.isMonitoring())
        await scanner.stop()
        #expect(!(await scanner.isMonitoring()))
        // The scanner deliberately exposes no account identifier: all results are device totals.
        #expect(await scanner.refresh(now: now, calendar: utc).todayTokens == 0)
    }

    private func meta(_ id: String, parent: String? = nil) -> String {
        let parentField = parent.map { ",\"forked_from_id\":\"\($0)\"" } ?? ""
        return "{\"timestamp\":\"2026-09-04T00:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"\(parentField)}}"
    }
    private func legacy(at timestamp: String, total: Int) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)}}}}"
    }
    private func modern(at timestamp: String, response: String, tokens: Int) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"token_usage_record\",\"payload\":{\"response_id\":\"\(response)\",\"usage\":{\"total_tokens\":\(tokens)}}}"
    }
    private func turnContext(_ model: String) -> String {
        "{\"timestamp\":\"2026-09-04T00:00:00Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"\(model)\"}}"
    }
    private func modernDetailed(at timestamp: String, response: String, input: Int, cached: Int, output: Int, reasoning: Int, model: String? = nil) -> String {
        let modelField = model.map { ",\"model\":\"\($0)\"" } ?? ""
        return "{\"timestamp\":\"\(timestamp)\",\"type\":\"token_usage_record\",\"payload\":{\"response_id\":\"\(response)\"\(modelField),\"usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":\(reasoning),\"total_tokens\":\(input + output)}}}"
    }
    private func legacyDetailed(at timestamp: String, cumulative: (Int, Int, Int, Int, Int), last: (Int, Int, Int, Int, Int)) -> String {
        func tuple(_ value: (Int, Int, Int, Int, Int)) -> String {
            "{\"total_tokens\":\(value.0),\"input_tokens\":\(value.1),\"cached_input_tokens\":\(value.2),\"output_tokens\":\(value.3),\"reasoning_output_tokens\":\(value.4)}"
        }
        return "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":\(tuple(cumulative)),\"last_token_usage\":\(tuple(last))}}}"
    }
}

private struct Fixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "local-token-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "sessions"), withIntermediateDirectories: true)
    }
    func file(day: String, name: String, archived: Bool = false) throws -> URL {
        let base = root.appending(path: archived ? "archived_sessions" : "sessions", directoryHint: .isDirectory)
        let directory = day.isEmpty ? base : base.appending(path: day, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = directory.appending(path: name)
        if !FileManager.default.fileExists(atPath: result.path) { FileManager.default.createFile(atPath: result.path, contents: nil) }
        return result
    }
    func append(_ lines: [String], to url: URL) throws { try appendRaw(lines.joined(separator: "\n") + "\n", to: url) }
    func appendRaw(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
