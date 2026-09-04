import Foundation

struct LocalModelTokenUsage: Equatable, Sendable, Identifiable {
    let model: String
    let todayTokens: Int
    let sevenDayTokens: Int
    let thirtyDayTokens: Int

    var id: String { model }
}

struct LocalModelUsageSummary: Equatable, Sendable {
    let models: [LocalModelTokenUsage]
    let coverageStartedAt: Date?
    let scannedAt: Date
}

actor LocalSessionUsageScanner {
    private let roots: [URL]
    private let fileManager: FileManager

    init(codexHome: URL? = nil, fileManager: FileManager = .default) {
        let home = codexHome ?? fileManager.homeDirectoryForCurrentUser.appending(
            path: ".codex",
            directoryHint: .isDirectory
        )
        roots = [
            home.appending(path: "sessions", directoryHint: .isDirectory),
            home.appending(path: "archived_sessions", directoryHint: .isDirectory),
        ]
        self.fileManager = fileManager
    }

    func scan(
        now: Date = Date(),
        calendar: Calendar = BeijingDateTimeFormatter.calendar,
        historyDays: Int = 1
    ) -> LocalModelUsageSummary {
        let today = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let boundedHistoryDays = min(max(historyDays, 1), 30)
        let fileCutoff = calendar.date(
            byAdding: .day,
            value: -(boundedHistoryDays - 1),
            to: today
        ) ?? today

        var totals: [String: (today: Int, seven: Int, thirty: Int)] = [:]
        var earliest: Date?

        for file in candidateFiles(modifiedAfter: fileCutoff) {
            scanFile(file) { timestamp, model, tokens in
                guard timestamp >= thirtyDayStart, timestamp <= now, tokens > 0 else { return }
                earliest = min(earliest ?? timestamp, timestamp)
                var value = totals[model, default: (0, 0, 0)]
                value.thirty += tokens
                if timestamp >= sevenDayStart { value.seven += tokens }
                if timestamp >= today { value.today += tokens }
                totals[model] = value
            }
        }

        let models = totals.map { model, value in
            LocalModelTokenUsage(
                model: model,
                todayTokens: value.today,
                sevenDayTokens: value.seven,
                thirtyDayTokens: value.thirty
            )
        }.sorted {
            if $0.thirtyDayTokens == $1.thirtyDayTokens { return $0.model < $1.model }
            return $0.thirtyDayTokens > $1.thirtyDayTokens
        }
        return LocalModelUsageSummary(models: models, coverageStartedAt: earliest, scannedAt: now)
    }

    private func candidateFiles(modifiedAfter cutoff: Date) -> [URL] {
        roots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var files: [URL] = []
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                ), values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff
                else { continue }
                files.append(url)
            }
            return files
        }
    }

    private func scanFile(
        _ url: URL,
        onUsage: (_ timestamp: Date, _ model: String, _ tokens: Int) -> Void
    ) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }

        var currentModel = "Unknown model"
        var lastCumulativeTokens = 0
        let isoWithFractionalSeconds = ISO8601DateFormatter()
        isoWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoWithoutFractionalSeconds = ISO8601DateFormatter()
        isoWithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        let turnContextMarker = Data(#""turn_context""#.utf8)
        let tokenCountMarker = Data(#""token_count""#.utf8)
        var searchStart = data.startIndex

        while searchStart < data.endIndex {
            let searchRange = searchStart..<data.endIndex
            let nextContext = data.range(of: turnContextMarker, in: searchRange)?.lowerBound
            let nextToken = data.range(of: tokenCountMarker, in: searchRange)?.lowerBound
            guard let markerStart = [nextContext, nextToken].compactMap({ $0 }).min() else { break }

            let lineStart = data[searchStart..<markerStart].lastIndex(of: 0x0A)
                .map { data.index(after: $0) } ?? searchStart
            let lineEnd = data[markerStart..<data.endIndex].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else {
                searchStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
                continue
            }

            if type == "turn_context", let model = payload["model"] as? String, !model.isEmpty {
                currentModel = model
            } else if type == "event_msg",
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any],
                      let cumulative = Self.integer(total["total_tokens"]),
                      let timestampText = object["timestamp"] as? String,
                      let timestamp = isoWithFractionalSeconds.date(from: timestampText)
                        ?? isoWithoutFractionalSeconds.date(from: timestampText) {
                // Codex emits cumulative session usage and can repeat the same value for
                // rate-limit-only events. Delta accounting avoids counting those repeats.
                let delta = cumulative >= lastCumulativeTokens
                    ? cumulative - lastCumulativeTokens
                    : cumulative
                lastCumulativeTokens = cumulative
                onUsage(timestamp, currentModel, delta)
            }
            searchStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return nil
    }
}
