import Foundation
import Testing
@testable import CodexAccountSwitcher

@Suite(.serialized)
struct TaskUsageAnalyticsTests {
    @Test func singleTaskSnapshotsProduceMeasuredQuotaRateAndSolBaseline() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = TaskUsageTracker(codexHome: root)
        let account = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let reset = Date(timeIntervalSince1970: 100_000)
        _ = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 90, resetsAt: reset, weeklyUsedPercent: 10),
            tasks: [task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 100, duration: 0, at: start)],
            sampledAt: start
        )
        let result = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 88, resetsAt: reset, weeklyUsedPercent: 12),
            tasks: [task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 200, duration: 600, at: start)],
            sampledAt: start.addingTimeInterval(60)
        )
        #expect(result.tasks.first?.weeklyQuotaPoints == 2)
        #expect(result.tasks.first?.evidence == .measuredSingleTask)
        #expect(result.comparisons.first?.quotaMultiplier == 1)
        #expect(result.comparisons.first?.quotaPointsPer10ActiveMinutes == 2)
    }

    @Test func concurrentTasksStayUnattributedAndDoNotTrainMultiplier() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = TaskUsageTracker(codexHome: root)
        let account = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        let reset = Date(timeIntervalSince1970: 200_000)
        let initial = [
            task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 100, duration: 0, at: start),
            task(id: "astra", model: "gpt-6-astra", effort: "high", total: 100, duration: 0, at: start),
        ]
        _ = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 95, resetsAt: reset, weeklyUsedPercent: 5),
            tasks: initial,
            sampledAt: start
        )
        let changed = [
            task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 200, duration: 600, at: start),
            task(id: "astra", model: "gpt-6-astra", effort: "high", total: 300, duration: 600, at: start),
        ]
        let result = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 92, resetsAt: reset, weeklyUsedPercent: 8),
            tasks: changed,
            sampledAt: start.addingTimeInterval(60)
        )
        let sol = result.tasks.first { $0.id == "sol" }
        let astra = result.tasks.first { $0.id == "astra" }
        #expect(sol?.weeklyQuotaPoints == nil)
        #expect(astra?.weeklyQuotaPoints == nil)
        #expect(sol?.evidence == .tokenOnly)
        #expect(result.unallocatedWeeklyQuotaPoints == 3)
        #expect(result.comparisons.allSatisfy { $0.quotaMultiplier == nil })
    }

    @Test func astraQuotaBurnRateIsComparedDirectlyWithSolMedium() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = TaskUsageTracker(codexHome: root)
        let account = UUID()
        let start = Date(timeIntervalSince1970: 2_500)
        let reset = Date(timeIntervalSince1970: 250_000)
        let initial = [
            task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 100, duration: 0, at: start),
            task(id: "astra", model: "gpt-6-astra", effort: "high", total: 100, duration: 0, at: start),
        ]
        _ = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 95, resetsAt: reset, weeklyUsedPercent: 5),
            tasks: initial,
            sampledAt: start
        )
        let afterSol = [
            task(id: "sol", model: "gpt-5.6-sol", effort: "medium", total: 200, duration: 600, at: start),
            initial[1],
        ]
        _ = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 94, resetsAt: reset, weeklyUsedPercent: 6),
            tasks: afterSol,
            sampledAt: start.addingTimeInterval(600)
        )
        let afterAstra = [
            afterSol[0],
            task(id: "astra", model: "gpt-6-astra", effort: "high", total: 200, duration: 600, at: start),
        ]
        let result = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 91, resetsAt: reset, weeklyUsedPercent: 9),
            tasks: afterAstra,
            sampledAt: start.addingTimeInterval(1_200)
        )
        let sol = result.comparisons.first { $0.model == "gpt-5.6-sol" && $0.effort == "medium" }
        let astra = result.comparisons.first { $0.model == "gpt-6-astra" && $0.effort == "high" }
        #expect(sol?.quotaPointsPer10ActiveMinutes == 1)
        #expect(sol?.quotaMultiplier == 1)
        #expect(astra?.quotaPointsPer10ActiveMinutes == 3)
        #expect(astra?.quotaMultiplier == 3)
    }

    @Test func resetWindowDoesNotBecomeNegativeConsumption() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = TaskUsageTracker(codexHome: root)
        let account = UUID()
        let start = Date(timeIntervalSince1970: 3_000)
        _ = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 20, resetsAt: Date(timeIntervalSince1970: 4_000), weeklyUsedPercent: 80),
            tasks: [task(id: "one", model: "gpt-5.6-sol", effort: "medium", total: 100, duration: 0, at: start)],
            sampledAt: start
        )
        let result = await tracker.record(
            accountID: account,
            usage: WeeklyUsage(remainingPercent: 99, resetsAt: Date(timeIntervalSince1970: 700_000), weeklyUsedPercent: 1),
            tasks: [task(id: "one", model: "gpt-5.6-sol", effort: "medium", total: 200, duration: 600, at: start)],
            sampledAt: start.addingTimeInterval(60)
        )
        #expect(result.tasks.first?.weeklyQuotaPoints == nil)
    }

    private func task(id: String, model: String, effort: String, total: Int, duration: TimeInterval, at start: Date) -> LocalTaskTokenUsage {
        let components = LocalTokenComponents(total: total, uncachedInput: total, cachedInput: 0, output: 0)
        return LocalTaskTokenUsage(
            id: id,
            parentID: nil,
            startedAt: start,
            latestEventAt: start.addingTimeInterval(duration),
            usage: components,
            profiles: [LocalTaskProfileUsage(model: model, effort: effort, usage: components)],
            activeDuration: duration
        )
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
