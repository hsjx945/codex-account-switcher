import AppKit
import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    let tokenActivity: TokenActivity?
    let localModelUsage: LocalModelUsageSummary?
    let showsTokenActivity: Bool
    let warmupStatus: WarmupRecord?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            titleRow
            usageContent

            if isActive, showsTokenActivity {
                currentTokenContent
            }

            if let warmupStatus {
                warmupContent(warmupStatus)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive ? Color.orange.opacity(0.34) : Color.primary.opacity(0.09),
                    lineWidth: 1
                )
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Text(account.preferredLabel)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let message = usageState.refreshError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(message)
                    .accessibilityLabel(message)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                if isActive {
                    StatusTag(
                        title: L10n.string("active", language: language),
                        foreground: Color(nsColor: .systemGreen),
                        background: Color(nsColor: .systemGreen).opacity(0.13)
                    )
                }

                if let badge = account.subscriptionBadge {
                    StatusTag(
                        title: badge,
                        foreground: planForeground,
                        background: planBackground
                    )
                }
            }
            .fixedSize()
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private var usageContent: some View {
        switch usageState {
        case .idle:
            Text("\(L10n.string("usage", language: language)) —")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(L10n.string("usage_unavailable", language: language))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .help(message)
        case let .loaded(usage), let .stale(usage, _):
            VStack(spacing: 9) {
                if shouldShowFiveHourUsage,
                   let remaining = usage.fiveHourRemainingPercent,
                   let resetsAt = usage.fiveHourResetsAt {
                    limitRow(
                        title: L10n.string("five_hour", language: language),
                        remainingPercent: remaining,
                        resetsAt: resetsAt
                    )
                }

                limitRow(
                    title: L10n.string("weekly", language: language),
                    remainingPercent: usage.remainingPercent,
                    resetsAt: usage.resetsAt
                )
            }
        }
    }

    private func limitRow(
        title: String,
        remainingPercent: Int,
        resetsAt: Date
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)

            UsageBar(remainingPercent: remainingPercent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(title)
                .accessibilityValue("\(remainingPercent)\(L10n.string("left", language: language))")

            Text("\(remainingPercent)%")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .frame(width: 42, alignment: .trailing)

            Text(resetText(for: resetsAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var currentTokenContent: some View {
        Divider()

        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string("today_token", language: language))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if let todayTokens {
                Text(formatTokens(todayTokens))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
            } else {
                Text(L10n.string("token_scanning_short", language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayTokens: Int? {
        if let localModelUsage {
            return localModelUsage.models.reduce(0) { $0 + $1.todayTokens }
        }
        return tokenActivity?.tokensForToday()
    }

    private func warmupContent(_ record: WarmupRecord) -> some View {
        let key = switch record.outcome {
        case .attempting: "warmup_attempting"
        case .confirmed: "warmup_confirmed"
        case .unconfirmed: "warmup_unconfirmed"
        case .failed: "warmup_failed"
        }
        return Text("\(L10n.string(key, language: language)) · \(BeijingDateTimeFormatter.string(from: record.attemptedAt))")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var rowBackground: Color {
        if isActive {
            return Color.orange.opacity(isHovering ? 0.085 : 0.055)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.82 : 0.56)
    }

    private var shouldShowFiveHourUsage: Bool {
        showsFiveHourUsage && account.supportsFiveHourUsage
    }

    private var planForeground: Color {
        switch account.planType?.lowercased() {
        case "plus": Color.orange
        case "team": Color.blue
        case "prolite": Color.purple
        case "pro": Color.pink
        default: Color.secondary
        }
    }

    private var planBackground: Color {
        planForeground.opacity(0.12)
    }

    private func resetText(for resetsAt: Date) -> String {
        BeijingDateTimeFormatter.string(from: resetsAt)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return String(tokens)
    }
}

private struct StatusTag: View {
    let title: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct UsageBar: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Color.orange.opacity(0.78))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(minWidth: 64, maxWidth: .infinity, minHeight: 6, maxHeight: 6)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }
}
