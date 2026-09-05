import AppKit
import Foundation
import SwiftUI

/// Renders real SwiftUI account rows with synthetic data; never opens live account storage.
@main
struct RenderUIChecks {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let reset = ISO8601DateFormatter().date(from: "2026-09-05T04:58:00Z")!
        let todayKey = TokenActivity.dateKey()
        let profiles = [
            AccountProfile(id: UUID(), displayName: "No Today Data", email: "missing@example.com", accountID: nil, planType: "prolite", createdAt: reset),
            AccountProfile(id: UUID(), displayName: "Today Zero", email: "zero@example.com", accountID: nil, planType: "plus", createdAt: reset),
            AccountProfile(id: UUID(), displayName: "Reading", email: "reading@example.com", accountID: nil, planType: "team", createdAt: reset),
            AccountProfile(id: UUID(), displayName: "Read Failed", email: "failed@example.com", accountID: nil, planType: "free", createdAt: reset),
        ]
        let activities = [
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 557_900_000)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: todayKey, tokens: 0)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 12_345)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
            TokenActivity(
                dailyBuckets: [DailyTokenUsage(startDate: todayKey, tokens: 456)],
                modelBreakdown: [],
                localModelCoverageStartedAt: nil
            ),
        ]
        for (language, name) in [(AppLanguage.simplifiedChinese, "zh"), (.english, "en")] {
            for (scheme, theme) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                let rows = profiles.enumerated().map { index, profile in
                    AccountRow(
                        account: profile,
                        usageState: .loaded(WeeklyUsage(remainingPercent: index.isMultiple(of: 2) ? 50 : 0, resetsAt: reset, fiveHourRemainingPercent: 100, fiveHourResetsAt: reset)),
                        isActive: index == 0, language: language, showsFiveHourUsage: true,
                        tokenActivity: activities[index],
                        tokenReportingDate: todayKey, tokenActivityRefreshFinished: true,
                        showsTokenActivity: true, warmupStatus: nil,
                        tokenRefreshError: index == 3 ? "fixture offline" : nil,
                        tokenFetchedAt: reset,
                        tokenRefreshPending: index == 2
                    )
                }
                let content = VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                    }
                }
                .padding(9)
                .frame(width: 420)
                .background(scheme == .dark ? Color.black : Color(white: 0.96))
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try png.write(to: output.appending(path: "accounts-\(name)-\(theme).png"))
            }
        }
        print("Rendered four SwiftUI account layouts with synthetic data")
    }
}
