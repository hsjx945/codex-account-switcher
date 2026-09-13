import Foundation

enum TaskQuotaEvidence: String, Codable, Sendable {
    case measuredSingleTask
    case tokenOnly
}

struct TaskUsageReport: Identifiable, Equatable, Sendable {
    let id: String
    let startedAt: Date
    let latestEventAt: Date
    let model: String?
    let effort: String?
    let usage: LocalTokenComponents
    let duration: TimeInterval
    let weeklyQuotaPoints: Double?
    let evidence: TaskQuotaEvidence
}

struct ModelEffortComparison: Identifiable, Equatable, Sendable {
    let model: String?
    let effort: String?
    let taskCount: Int
    let usage: LocalTokenComponents
    let activeDuration: TimeInterval
    let weeklyQuotaPoints: Double?
    let quotaMultiplier: Double?
    let quotaPointsPer10ActiveMinutes: Double?

    var id: String { Self.key(model: model, effort: effort) }

    static func key(model: String?, effort: String?) -> String {
        "\(model ?? "__unknown_model__")|\(effort ?? "__unknown_effort__")"
    }
}

struct TaskUsageAnalyticsSnapshot: Equatable, Sendable {
    let tasks: [TaskUsageReport]
    let comparisons: [ModelEffortComparison]
    let unallocatedWeeklyQuotaPoints: Double
    let sampledAt: Date?

    static let empty = TaskUsageAnalyticsSnapshot(
        tasks: [], comparisons: [], unallocatedWeeklyQuotaPoints: 0, sampledAt: nil
    )
}

/// Learns the subscription quota conversion empirically from adjacent official
/// weekly snapshots. It stores only derived counters and opaque session IDs.
actor TaskUsageTracker {
    private struct ProfileCounter: Codable, Equatable {
        var model: String?
        var effort: String?
        var usage: LocalTokenComponents
    }

    private struct TaskCounter: Codable, Equatable {
        var startedAt: Date
        var latestEventAt: Date
        var activeDuration: TimeInterval
        var profiles: [String: ProfileCounter]
    }

    private struct Observation: Codable, Equatable {
        var sampledAt: Date
        var weeklyUsedPercent: Double
        var resetsAt: Date?
        var tasks: [String: TaskCounter]
    }

    private struct Allocation: Codable, Equatable {
        var taskID: String
        var profileKey: String
        var weeklyQuotaPoints: Double
        var directActiveSeconds: TimeInterval
        var sampleCount: Int
    }

    private struct AccountLedger: Codable, Equatable {
        var latest: Observation?
        var allocations: [String: Allocation] = [:]
        var unallocatedWeeklyQuotaPoints = 0.0
    }

    private struct Storage: Codable, Equatable {
        var accounts: [String: AccountLedger] = [:]
    }

    private let cacheURL: URL
    private let fileManager: FileManager
    private var storage: Storage

    init(codexHome: URL? = nil, fileManager: FileManager = .default) {
        let environmentHome = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        let home = codexHome ?? environmentHome
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
        cacheURL = home.appending(path: ".cache/account-switcher-task-quota-v2.json")
        self.fileManager = fileManager
        storage = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Storage.self, from: $0) }
            ?? Storage()
    }

    func record(
        accountID: UUID,
        usage: WeeklyUsage,
        tasks: [LocalTaskTokenUsage],
        sampledAt: Date = Date()
    ) -> TaskUsageAnalyticsSnapshot {
        guard let used = usage.weeklyUsedPercent, used.isFinite, (0...100).contains(used) else {
            return snapshot(accountID: accountID, tasks: tasks, sampledAt: nil)
        }
        let accountKey = accountID.uuidString
        var ledger = storage.accounts[accountKey] ?? AccountLedger()
        let current = Observation(
            sampledAt: sampledAt,
            weeklyUsedPercent: used,
            resetsAt: usage.resetsAt,
            tasks: Self.counters(tasks)
        )
        if let previous = ledger.latest,
           Self.sameWindow(previous.resetsAt, current.resetsAt),
           current.sampledAt > previous.sampledAt,
           current.weeklyUsedPercent >= previous.weeklyUsedPercent {
            let quotaDelta = current.weeklyUsedPercent - previous.weeklyUsedPercent
            if quotaDelta > 0 {
                let increments = Self.increments(from: previous.tasks, to: current.tasks)
                if increments.count == 1, let increment = increments.first {
                    let key = "\(increment.taskID)|\(increment.profileKey)"
                    var allocation = ledger.allocations[key] ?? Allocation(
                        taskID: increment.taskID,
                        profileKey: increment.profileKey,
                        weeklyQuotaPoints: 0,
                        directActiveSeconds: 0,
                        sampleCount: 0
                    )
                    allocation.weeklyQuotaPoints += quotaDelta
                    allocation.directActiveSeconds += increment.activeSeconds
                    allocation.sampleCount += 1
                    ledger.allocations[key] = allocation
                } else {
                    ledger.unallocatedWeeklyQuotaPoints += quotaDelta
                }
            }
        }
        ledger.latest = current
        storage.accounts[accountKey] = ledger
        save()
        return snapshot(accountID: accountID, tasks: tasks, sampledAt: sampledAt)
    }

    func snapshot(accountID: UUID, tasks: [LocalTaskTokenUsage], sampledAt: Date? = nil) -> TaskUsageAnalyticsSnapshot {
        let ledger = storage.accounts[accountID.uuidString] ?? AccountLedger()
        let allocationByTask = Dictionary(grouping: ledger.allocations.values, by: \.taskID)
        let reports = tasks.map { task -> TaskUsageReport in
            let allocations = allocationByTask[task.id] ?? []
            let points = allocations.isEmpty ? nil : allocations.reduce(0) { $0 + $1.weeklyQuotaPoints }
            let evidence: TaskQuotaEvidence = allocations.isEmpty ? .tokenOnly : .measuredSingleTask
            let dominant = task.profiles.max { $0.usage.total < $1.usage.total }
            return TaskUsageReport(
                id: task.id,
                startedAt: task.startedAt,
                latestEventAt: task.latestEventAt,
                model: dominant?.model,
                effort: dominant?.effort,
                usage: task.usage,
                duration: task.duration,
                weeklyQuotaPoints: points,
                evidence: evidence
            )
        }
        return TaskUsageAnalyticsSnapshot(
            tasks: reports,
            comparisons: Self.comparisons(tasks: tasks, allocations: ledger.allocations),
            unallocatedWeeklyQuotaPoints: ledger.unallocatedWeeklyQuotaPoints,
            sampledAt: sampledAt ?? ledger.latest?.sampledAt
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        do {
            try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch {
            // Losing derived analytics must not affect account switching or quota display.
        }
    }

    private struct Increment {
        let taskID: String
        let profileKey: String
        let activeSeconds: TimeInterval
    }

    private static func counters(_ tasks: [LocalTaskTokenUsage]) -> [String: TaskCounter] {
        Dictionary(uniqueKeysWithValues: tasks.map { task in
            (task.id, TaskCounter(
                startedAt: task.startedAt,
                latestEventAt: task.latestEventAt,
                activeDuration: task.duration,
                profiles: Dictionary(uniqueKeysWithValues: task.profiles.map { profile in
                    (profile.id, ProfileCounter(model: profile.model, effort: profile.effort, usage: profile.usage))
                })
            ))
        })
    }

    private static func increments(from old: [String: TaskCounter], to new: [String: TaskCounter]) -> [Increment] {
        new.flatMap { taskID, task in
            task.profiles.compactMap { profileKey, profile in
                let previous = old[taskID]?.profiles[profileKey]?.usage
                let delta = subtract(profile.usage, previous)
                guard delta.total > 0 else { return nil }
                let oldDuration = old[taskID]?.activeDuration ?? 0
                return Increment(
                    taskID: taskID,
                    profileKey: profileKey,
                    activeSeconds: max(0, task.activeDuration - oldDuration)
                )
            }
        }
    }

    private static func comparisons(tasks: [LocalTaskTokenUsage], allocations: [String: Allocation]) -> [ModelEffortComparison] {
        struct Aggregate {
            var usage = ComponentsAggregate()
            var taskIDs = Set<String>()
            var duration = 0.0
            var quota = 0.0
            var measuredSeconds = 0.0
            var hasQuota = false
        }
        var grouped: [String: (String?, String?, Aggregate)] = [:]
        for task in tasks {
            for profile in task.profiles {
                let key = profile.id
                var item = grouped[key] ?? (profile.model, profile.effort, Aggregate())
                item.2.usage.add(profile.usage)
                if item.2.taskIDs.insert(task.id).inserted { item.2.duration += task.duration }
                grouped[key] = item
            }
        }
        for allocation in allocations.values {
            guard var item = grouped[allocation.profileKey] else { continue }
            item.2.quota += allocation.weeklyQuotaPoints
            item.2.measuredSeconds += allocation.directActiveSeconds
            item.2.hasQuota = true
            grouped[allocation.profileKey] = item
        }
        let baselineKey = ModelEffortComparison.key(model: "gpt-5.6-sol", effort: "medium")
        let baselineRate = grouped[baselineKey].flatMap { item -> Double? in
            item.2.measuredSeconds > 0 ? item.2.quota / item.2.measuredSeconds * 600 : nil
        }
        return grouped.map { key, item in
            let components = item.2.usage.components
            let rate = item.2.measuredSeconds > 0 ? item.2.quota / item.2.measuredSeconds * 600 : nil
            return ModelEffortComparison(
                model: item.0,
                effort: item.1,
                taskCount: item.2.taskIDs.count,
                usage: components,
                activeDuration: item.2.duration,
                weeklyQuotaPoints: item.2.hasQuota ? item.2.quota : nil,
                quotaMultiplier: rate.flatMap { value in baselineRate.map { value / $0 } },
                quotaPointsPer10ActiveMinutes: rate
            )
        }.sorted { lhs, rhs in
            if lhs.usage.total != rhs.usage.total { return lhs.usage.total > rhs.usage.total }
            return keyFor(lhs) < keyFor(rhs)
        }
    }

    private struct ComponentsAggregate {
        var total = 0, uncached = 0, cached = 0, output = 0
        var complete = true
        mutating func add(_ value: LocalTokenComponents) {
            total += value.total
            guard let u = value.uncachedInput, let c = value.cachedInput, let o = value.output else {
                complete = false; return
            }
            uncached += u; cached += c; output += o
        }
        var components: LocalTokenComponents {
            LocalTokenComponents(total: total, uncachedInput: complete ? uncached : nil, cachedInput: complete ? cached : nil, output: complete ? output : nil)
        }
    }

    private static func subtract(_ current: LocalTokenComponents, _ previous: LocalTokenComponents?) -> LocalTokenComponents {
        guard let previous else { return current }
        return LocalTokenComponents(
            total: max(0, current.total - previous.total),
            uncachedInput: subtract(current.uncachedInput, previous.uncachedInput),
            cachedInput: subtract(current.cachedInput, previous.cachedInput),
            output: subtract(current.output, previous.output)
        )
    }

    private static func subtract(_ current: Int?, _ previous: Int?) -> Int? {
        guard let current else { return nil }
        return max(0, current - (previous ?? 0))
    }

    private static func sameWindow(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 60
        case (nil, nil): true
        default: false
        }
    }

    private static func keyFor(_ item: ModelEffortComparison) -> String {
        ModelEffortComparison.key(model: item.model, effort: item.effort)
    }
}
