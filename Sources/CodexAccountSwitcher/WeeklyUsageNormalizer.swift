import Foundation

struct RateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval?
}

enum WeeklyUsageNormalizer {
    static let fiveHourMinutes = 5 * 60
    static let minimumWeeklyMinutes = 6 * 24 * 60
    static let maximumWeeklyMinutes = 8 * 24 * 60

    static func normalize(_ windows: [RateLimitWindow]) throws -> WeeklyUsage {
        guard let weekly = windows
            .filter({ minimumWeeklyMinutes...maximumWeeklyMinutes ~= $0.windowDurationMins })
            .max(by: { $0.windowDurationMins < $1.windowDurationMins })
        else {
            throw CodexClientError.weeklyUsageUnavailable
        }

        let fiveHour = windows.first { $0.windowDurationMins == fiveHourMinutes }

        return WeeklyUsage(
            remainingPercent: try remainingPercent(for: weekly),
            resetsAt: weekly.resetsAt.map(Date.init(timeIntervalSince1970:)),
            fiveHourRemainingPercent: try fiveHour.map { try remainingPercent(for: $0) },
            fiveHourResetsAt: fiveHour?.resetsAt.map(Date.init(timeIntervalSince1970:)),
            weeklyUsedPercent: weekly.usedPercent
        )
    }

    private static func remainingPercent(for window: RateLimitWindow) throws -> Int {
        guard window.usedPercent.isFinite else { throw CodexClientError.malformedResponse }
        // Clamp while still floating point; converting an unbounded server value traps.
        return Int((100 - min(100, max(0, window.usedPercent))).rounded())
    }
}
