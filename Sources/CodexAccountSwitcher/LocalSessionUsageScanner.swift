import CoreFoundation
import Foundation

enum LocalTokenScanState: Equatable, Sendable { case idle, monitoring, failed(String) }

struct LocalTokenComponents: Equatable, Sendable {
    let total: Int
    let uncachedInput: Int?
    let cachedInput: Int?
    let output: Int?
}

struct LocalModelTokenUsage: Equatable, Sendable, Identifiable {
    let model: String?
    let usage: LocalTokenComponents
    var id: String { model ?? "__unknown_model__" }
}

struct LocalTokenUsageSnapshot: Equatable, Sendable {
    let usage: LocalTokenComponents?
    let models: [LocalModelTokenUsage]
    let latestEventAt: Date?
    let scannedAt: Date
    let state: LocalTokenScanState
    var todayTokens: Int? { usage?.total }
}

enum LocalSessionUsageError: LocalizedError, Equatable {
    case noSessionDirectory, unreadableFile(String), tokenOverflow
    var errorDescription: String? {
        switch self {
        case .noSessionDirectory: "No local Codex session directory is available."
        case let .unreadableFile(path): "Could not read local Codex session data: \(path)"
        case .tokenOverflow: "Local token total exceeded the supported range."
        }
    }
}

actor LocalSessionUsageScanner {
    private struct UsageTuple: Equatable {
        let total: Int
        let input: Int
        let cached: Int
        let output: Int
        let reasoning: Int

        var components: LocalTokenComponents? {
            guard cached <= input else { return nil }
            return LocalTokenComponents(total: total, uncachedInput: input - cached, cachedInput: cached, output: output)
        }
    }
    private struct LegacyReplayKey: Equatable { let cumulative: UsageTuple; let last: UsageTuple? }
    private enum EventKind: Equatable { case legacy(LegacyReplayKey?), response(String) }
    private struct UsageEvent: Equatable {
        let timestamp: Date
        let usage: LocalTokenComponents
        let model: String?
        let kind: EventKind
    }
    private struct FileState {
        var identity: String
        var modificationDate: Date?
        var offset = 0
        var parsedSize = 0
        var pending = Data()
        var currentModel: String?
        var lastCumulativeTotal = 0
        var lastCumulativeTuple: UsageTuple?
        var sessionID: String?
        var parentID: String?
        var events: [UsageEvent] = []
        var modernBoundary: Int?
        var parseError: String?
    }
    private struct Aggregate {
        var total = 0
        var uncached = 0
        var cached = 0
        var output = 0
        var componentsComplete = true

        mutating func add(_ usage: LocalTokenComponents) throws {
            total = try Self.adding(total, usage.total)
            guard let uncachedInput = usage.uncachedInput, let cachedInput = usage.cachedInput, let outputTokens = usage.output else {
                componentsComplete = false
                return
            }
            uncached = try Self.adding(uncached, uncachedInput)
            cached = try Self.adding(cached, cachedInput)
            output = try Self.adding(output, outputTokens)
        }
        var usage: LocalTokenComponents {
            LocalTokenComponents(total: total, uncachedInput: componentsComplete ? uncached : nil, cachedInput: componentsComplete ? cached : nil, output: componentsComplete ? output : nil)
        }
        private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
            guard rhs >= 0, lhs <= Int.max - rhs else { throw LocalSessionUsageError.tokenOverflow }
            return lhs + rhs
        }
    }

    private let roots: [URL]
    private let fileManager: FileManager
    private var files: [URL: FileState] = [:]
    private var monitorTask: Task<Void, Never>?
    private var lastSnapshot: LocalTokenUsageSnapshot?

    init(codexHome: URL? = nil, fileManager: FileManager = .default) {
        let environmentHome = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let home = codexHome ?? environmentHome ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
        roots = [home.appending(path: "sessions", directoryHint: .isDirectory), home.appending(path: "archived_sessions", directoryHint: .isDirectory)]
        self.fileManager = fileManager
    }

    func refresh(now: Date = Date(), calendar: Calendar = BeijingDateTimeFormatter.calendar) -> LocalTokenUsageSnapshot {
        do {
            let candidates = try candidateFiles(modifiedAfter: calendar.startOfDay(for: now))
            for url in candidates { try ingest(url) }
            files = files.filter { candidates.contains($0.key) }
            if let error = files.values.compactMap(\.parseError).first { throw LocalSessionUsageError.unreadableFile(error) }
            let result = try summarize(now: now, calendar: calendar)
            let snapshot = LocalTokenUsageSnapshot(usage: result.usage, models: result.models, latestEventAt: result.latest, scannedAt: now, state: monitorTask == nil ? .idle : .monitoring)
            lastSnapshot = snapshot
            return snapshot
        } catch {
            let snapshot = LocalTokenUsageSnapshot(usage: nil, models: [], latestEventAt: lastSnapshot?.latestEventAt, scannedAt: now, state: .failed(error.localizedDescription))
            lastSnapshot = snapshot
            return snapshot
        }
    }

    func start(interval: Duration = .seconds(1), onUpdate: @escaping @MainActor @Sendable (LocalTokenUsageSnapshot) -> Void) {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await onUpdate(await self.refresh())
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }
    func stop() { monitorTask?.cancel(); monitorTask = nil }
    func isMonitoring() -> Bool { monitorTask != nil }

    private func candidateFiles(modifiedAfter cutoff: Date) throws -> Set<URL> {
        var foundRoot = false
        var result = Set<URL>()
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            foundRoot = true
            var traversalError: Error?
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles], errorHandler: { _, error in traversalError = error; return false }) else {
                throw LocalSessionUsageError.unreadableFile(root.lastPathComponent)
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values: URLResourceValues
                do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]) }
                catch { throw LocalSessionUsageError.unreadableFile(url.lastPathComponent) }
                if values.isRegularFile == true, (values.contentModificationDate ?? .distantPast) >= cutoff { result.insert(url) }
            }
            if traversalError != nil { throw LocalSessionUsageError.unreadableFile(root.lastPathComponent) }
        }
        guard foundRoot else { throw LocalSessionUsageError.noSessionDirectory }
        return result
    }

    private func ingest(_ url: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fileManager.attributesOfItem(atPath: url.path) }
        catch { throw LocalSessionUsageError.unreadableFile(url.lastPathComponent) }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        let identity = String(describing: attributes[.systemFileNumber] ?? url.path)
        var state = files[url] ?? FileState(identity: identity)
        if state.identity != identity || size < state.offset
            || (size == state.offset && state.modificationDate != nil && state.modificationDate != modificationDate) {
            state = FileState(identity: identity)
        }
        state.modificationDate = modificationDate
        guard size > state.offset else { files[url] = state; return }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url); try handle.seek(toOffset: UInt64(state.offset)) }
        catch { throw LocalSessionUsageError.unreadableFile(url.lastPathComponent) }
        defer { try? handle.close() }
        do {
            while let appended = try handle.read(upToCount: 1_048_576), !appended.isEmpty {
                state.offset += appended.count
                state.pending.append(appended)
                var lineStart = state.pending.startIndex
                while let newline = state.pending[lineStart...].firstIndex(of: 0x0A) {
                    parseLine(Data(state.pending[lineStart..<newline]), into: &state)
                    state.parsedSize += state.pending.distance(from: lineStart, to: newline) + 1
                    lineStart = state.pending.index(after: newline)
                }
                if lineStart > state.pending.startIndex { state.pending.removeSubrange(state.pending.startIndex..<lineStart) }
            }
        } catch { throw LocalSessionUsageError.unreadableFile(url.lastPathComponent) }
        files[url] = state
    }

    private func parseLine(_ data: Data, into state: inout FileState) {
        let markers = ["\"session_meta\"", "\"turn_context\"", "\"token_usage_record\"", "\"token_count\""].map { Data($0.utf8) }
        guard markers.contains(where: { data.range(of: $0) != nil }) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else {
            state.parseError = "malformed local token event"; return
        }
        let payload = object["payload"] as? [String: Any]
        let tokenCount = type == "event_msg" && payload?["type"] as? String == "token_count"
        guard ["session_meta", "turn_context", "token_usage_record"].contains(type) || tokenCount else { return }
        guard let payload else { state.parseError = "local token event has no payload"; return }
        if type == "session_meta" {
            state.sessionID = payload["id"] as? String ?? payload["session_id"] as? String
            state.parentID = payload["forked_from_id"] as? String
                ?? payload["parent_thread_id"] as? String
                ?? (((payload["source"] as? [String: Any])?["subagent"] as? [String: Any])?["thread_spawn"] as? [String: Any])?["parent_thread_id"] as? String
            return
        }
        if type == "turn_context" {
            if let model = payload["model"] as? String, !model.isEmpty { state.currentModel = model }
            return
        }
        guard let timestampText = object["timestamp"] as? String, let timestamp = Self.parseDate(timestampText) else {
            state.parseError = "token event has no valid timestamp"; return
        }
        if type == "token_usage_record" {
            guard let responseID = payload["response_id"] as? String, !responseID.isEmpty,
                  let raw = payload["usage"] as? [String: Any], let usage = Self.modernUsage(raw)
            else { state.parseError = "invalid token_usage_record"; return }
            let model = (payload["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? state.currentModel
            if state.modernBoundary == nil { state.modernBoundary = state.events.count }
            state.events.append(UsageEvent(timestamp: timestamp, usage: usage, model: model, kind: .response(responseID)))
            return
        }
        if payload["info"] is NSNull { return }
        guard let info = payload["info"] as? [String: Any] else { state.parseError = "token_count event has no info"; return }
        guard let totalRaw = info["total_token_usage"] as? [String: Any], let cumulativeTotal = Self.integer(totalRaw["total_tokens"]) else {
            state.parseError = "invalid token_count total usage"; return
        }
        let cumulativeTuple = Self.tuple(totalRaw)
        let tupleFields = ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"]
        if tupleFields.contains(where: { totalRaw[$0] != nil }), cumulativeTuple == nil {
            state.parseError = "invalid token_count cumulative components"
            return
        }
        if let tuple = cumulativeTuple, tuple == state.lastCumulativeTuple { return }
        if cumulativeTuple == nil, cumulativeTotal == state.lastCumulativeTotal { return }
        let lastRaw = info["last_token_usage"] as? [String: Any]
        let lastTuple = lastRaw.flatMap(Self.tuple)
        if lastRaw != nil, lastTuple == nil {
            state.parseError = "invalid token_count last usage"
            return
        }
        let usage: LocalTokenComponents
        if let lastTuple, let components = lastTuple.components {
            usage = components
        } else {
            let delta = cumulativeTotal >= state.lastCumulativeTotal ? cumulativeTotal - state.lastCumulativeTotal : cumulativeTotal
            usage = LocalTokenComponents(total: delta, uncachedInput: nil, cachedInput: nil, output: nil)
        }
        state.lastCumulativeTotal = cumulativeTotal
        state.lastCumulativeTuple = cumulativeTuple
        let replayKey = cumulativeTuple.map { LegacyReplayKey(cumulative: $0, last: lastTuple) }
        state.events.append(UsageEvent(timestamp: timestamp, usage: usage, model: state.currentModel, kind: .legacy(replayKey)))
    }

    private func summarize(now: Date, calendar: Calendar) throws -> (usage: LocalTokenComponents, models: [LocalModelTokenUsage], latest: Date?) {
        let dayStart = calendar.startOfDay(for: now)
        let canonical = Dictionary(grouping: files, by: { $0.value.sessionID ?? $0.key.path }).compactMapValues { copies in
            copies.sorted { lhs, rhs in
                if lhs.value.events.count != rhs.value.events.count { return lhs.value.events.count > rhs.value.events.count }
                let lhsLatest = lhs.value.events.last?.timestamp ?? .distantPast, rhsLatest = rhs.value.events.last?.timestamp ?? .distantPast
                if lhsLatest != rhsLatest { return lhsLatest > rhsLatest }
                return lhs.value.parsedSize > rhs.value.parsedSize
            }.first?.value
        }
        var streams = canonical.mapValues(authoritativeEvents)
        for (id, state) in canonical {
            let prefixCount: Int
            if let parentID = state.parentID, let parent = canonical[parentID] {
                prefixCount = matchingLegacyPrefix(streams[id] ?? [], authoritativeEvents(parent))
            } else if state.parentID == nil {
                let child = streams[id] ?? []
                prefixCount = canonical.filter { $0.key != id && ($0.value.events.first?.timestamp ?? .distantFuture) < (state.events.first?.timestamp ?? .distantPast) }
                    .map { matchingLegacyPrefix(child, authoritativeEvents($0.value)) }
                    .filter { $0 >= 2 }.max() ?? 0
            } else { prefixCount = 0 }
            if prefixCount > 0 { streams[id]?.removeFirst(prefixCount) }
        }

        var aggregate = Aggregate(), byModel: [String?: Aggregate] = [:], latest: Date?
        var responses: [String: LocalTokenComponents] = [:]
        for events in streams.values {
            for event in events where event.timestamp >= dayStart && event.timestamp <= now {
                if case let .response(id) = event.kind {
                    if let previous = responses[id] {
                        guard previous == event.usage else { throw LocalSessionUsageError.unreadableFile("conflicting response_id usage") }
                        continue
                    }
                    responses[id] = event.usage
                }
                try aggregate.add(event.usage)
                var modelAggregate = byModel[event.model, default: Aggregate()]
                try modelAggregate.add(event.usage)
                byModel[event.model] = modelAggregate
                latest = max(latest ?? event.timestamp, event.timestamp)
            }
        }
        let unsortedModels: [LocalModelTokenUsage] = byModel.map { item in
            LocalModelTokenUsage(model: item.key, usage: item.value.usage)
        }
        let models = unsortedModels.sorted { lhs, rhs in
            if lhs.usage.total != rhs.usage.total { return lhs.usage.total > rhs.usage.total }
            return (lhs.model ?? "") < (rhs.model ?? "")
        }
        return (aggregate.usage, models, latest)
    }

    private func authoritativeEvents(_ state: FileState) -> [UsageEvent] {
        state.events.enumerated().compactMap { index, event in
            guard let boundary = state.modernBoundary else { return event }
            if case .response = event.kind { return event }
            return index < boundary ? event : nil
        }
    }

    private func matchingLegacyPrefix(_ child: [UsageEvent], _ parent: [UsageEvent]) -> Int {
        var count = 0
        while count < child.count, count < parent.count,
              case let .legacy(childKey?) = child[count].kind,
              case let .legacy(parentKey?) = parent[count].kind,
              childKey == parentKey { count += 1 }
        return count
    }

    private static func modernUsage(_ raw: [String: Any]) -> LocalTokenComponents? {
        let numericKeys = ["total_tokens", "input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"]
        guard numericKeys.allSatisfy({ raw[$0] == nil || integer(raw[$0]) != nil }) else { return nil }
        let suppliedTotal = integer(raw["total_tokens"])
        let input = integer(raw["input_tokens"]), cached = integer(raw["cached_input_tokens"]), output = integer(raw["output_tokens"])
        if let input, let cached, cached > input { return nil }
        if let output, let reasoning = integer(raw["reasoning_output_tokens"]), reasoning > output { return nil }
        if let input, let cached, let output, cached <= input, input <= Int.max - output {
            let total = input + output
            guard suppliedTotal == nil || suppliedTotal == total else { return nil }
            return LocalTokenComponents(total: total, uncachedInput: input - cached, cachedInput: cached, output: output)
        }
        guard let suppliedTotal else { return nil }
        return LocalTokenComponents(total: suppliedTotal, uncachedInput: nil, cachedInput: nil, output: nil)
    }

    private static func tuple(_ raw: [String: Any]) -> UsageTuple? {
        guard let total = integer(raw["total_tokens"]), let input = integer(raw["input_tokens"]),
              let cached = integer(raw["cached_input_tokens"]), let output = integer(raw["output_tokens"]),
              let reasoning = integer(raw["reasoning_output_tokens"]), cached <= input, reasoning <= output,
              input <= Int.max - output, total == input + output else { return nil }
        return UsageTuple(total: total, input: input, cached: cached, output: output, reasoning: reasoning)
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let integer = number.intValue, decimal = number.decimalValue
        guard decimal >= 0, decimal <= Decimal(Int.max), Decimal(integer) == decimal else { return nil }
        return integer
    }
    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
