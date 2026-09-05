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
        let profiles = [
            AccountProfile(id: UUID(), displayName: "Primary", email: "primary@example.com", accountID: nil, planType: "prolite", createdAt: reset),
            AccountProfile(id: UUID(), displayName: "Secondary", email: "very.long.account.name.for.layout@example.com", accountID: nil, planType: "plus", createdAt: reset),
        ]
        for (language, name) in [(AppLanguage.simplifiedChinese, "zh"), (.english, "en")] {
            for (scheme, theme) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                let content = VStack(spacing: 8) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        AccountRow(
                            account: profile,
                            usageState: .loaded(WeeklyUsage(remainingPercent: index == 0 ? 50 : 0, resetsAt: reset, fiveHourRemainingPercent: 100, fiveHourResetsAt: reset)),
                            isActive: index == 0, language: language, showsFiveHourUsage: true,
                            tokenActivity: TokenActivity(dailyBuckets: [DailyTokenUsage(startDate: "2026-09-04", tokens: 1234567)], modelBreakdown: [], localModelCoverageStartedAt: nil),
                            tokenReportingDate: "2026-09-04", tokenActivityRefreshFinished: true,
                            showsTokenActivity: true, warmupStatus: nil,
                            tokenRefreshError: index == 1 ? "fixture offline" : nil
                        )
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
