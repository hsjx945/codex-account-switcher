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

                if theme == "light" {
                    let examples = ["personal@example.com", "work@example.com", "client@example.com"]
                    let marketing = VStack(spacing: 8) {
                        ForEach(examples.indices, id: \.self) { index in
                            AccountRow(
                                account: AccountProfile(id: profiles[index].id, displayName: examples[index], email: examples[index], accountID: nil, planType: ["pro", "plus", "team"][index], createdAt: reset),
                                usageState: .loaded(WeeklyUsage(remainingPercent: [71, 97, 48][index], resetsAt: reset, fiveHourRemainingPercent: 85, fiveHourResetsAt: reset)),
                                isActive: index == 0, language: language, showsFiveHourUsage: true,
                                tokenActivity: nil, tokenReportingDate: nil, tokenActivityRefreshFinished: true,
                                showsTokenActivity: false, warmupStatus: nil
                            )
                        }
                    }
                    .padding(9)
                    .frame(width: 420)
                    .background(Color(white: 0.96))
                    .environment(\.colorScheme, .light)
                    let marketingRenderer = ImageRenderer(content: marketing)
                    marketingRenderer.scale = 2
                    guard let cgImage = marketingRenderer.cgImage,
                          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try data.write(to: output.appending(path: "website-\(name).png"))
                }

                let complete = LocalTokenComponents(total: 12_345, uncachedInput: 3_000, cachedInput: 8_000, output: 1_345)
                let missing = LocalTokenComponents(total: 9, uncachedInput: nil, cachedInput: nil, output: nil)
                let localStates: [(LocalTokenComponents?, [LocalModelTokenUsage], String, Bool)] = [
                    (nil, [], L10n.string("token_scanning", language: language), false),
                    (missing, [LocalModelTokenUsage(model: nil, usage: missing)], L10n.string("token_local_no_events_today", language: language), true),
                    (complete, [LocalModelTokenUsage(model: "gpt-5.6-sol", usage: complete)], String(format: L10n.string("token_local_last_event", language: language), BeijingDateTimeFormatter.stringWithSeconds(from: reset, language: language)), true),
                    (nil, [], String(format: L10n.string("token_local_failed", language: language), "fixture unavailable"), false),
                ]
                let tokenContent = VStack(spacing: 1) {
                    ForEach(localStates.indices, id: \.self) { stateIndex in
                        TokenTotalRow(
                            title: L10n.string("token_total_local_today", language: language),
                            usage: localStates[stateIndex].0,
                            models: localStates[stateIndex].1,
                            language: language,
                            statusText: localStates[stateIndex].2,
                            detailText: L10n.string("token_total_local_hint", language: language),
                            isRefreshing: stateIndex == 0,
                            initiallyExpanded: localStates[stateIndex].3
                        )
                    }
                }
                .frame(width: 420)
                .environment(\.colorScheme, scheme)
                let tokenRenderer = ImageRenderer(content: tokenContent)
                tokenRenderer.scale = 2
                guard let tokenImage = tokenRenderer.nsImage,
                      let tokenTIFF = tokenImage.tiffRepresentation,
                      let tokenPNG = NSBitmapImageRep(data: tokenTIFF)?.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try tokenPNG.write(to: output.appending(path: "local-token-states-\(name)-\(theme).png"))
            }
        }
        print("Rendered account layouts and four local-token states with synthetic data")
    }
}
