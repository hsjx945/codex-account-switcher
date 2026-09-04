import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    let nameStyle: AccountNameStyle
    let tokenActivity: TokenActivity?
    let showsTokenActivity: Bool
    let warmupStatus: WarmupRecord?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.primaryLabel(style: nameStyle))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let secondary = account.secondaryLabel(style: nameStyle) {
                        Text(secondary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if let badge = account.subscriptionBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.065), in: Capsule())
                }
                if isActive {
                    Text(L10n.string("active", language: language))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.09), in: Capsule())
                }
                if let usage = usageState.displayedUsage, !showsFiveHourUsage {
                    Text(resetText(for: usage))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else if let message = usageState.refreshError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help(message)
                        .accessibilityLabel(message)
                }
            }

            usageContent

            if showsTokenActivity, let tokenActivity {
                tokenContent(tokenActivity)
            }

            if let warmupStatus {
                warmupContent(warmupStatus)
            }
        }
        .frame(minHeight: 62)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.055),
                    lineWidth: 0.75
                )
        }
        .overlay(alignment: .leading) {
            if isActive {
                Capsule()
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 3, height: 30)
                    .padding(.leading, 5)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func tokenContent(_ activity: TokenActivity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 14) {
                tokenMetric("today", activity.tokens(inLastDays: 1))
                tokenMetric("last_7_days", activity.tokens(inLastDays: 7))
                tokenMetric("last_30_days", activity.tokens(inLastDays: 30))
            }
        }
    }

    private func tokenMetric(_ key: String, _ tokens: Int) -> some View {
        Text("\(L10n.string(key, language: language)) \(formatTokens(tokens))")
            .font(.system(size: 9.5).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func warmupContent(_ record: WarmupRecord) -> some View {
        let key = switch record.outcome {
        case .attempting: "warmup_attempting"
        case .confirmed: "warmup_confirmed"
        case .unconfirmed: "warmup_unconfirmed"
        case .failed: "warmup_failed"
        }
        let timestamp = BeijingDateTimeFormatter.string(from: record.attemptedAt)
        let model = record.model.map { " · \($0)" } ?? ""
        return Text("\(L10n.string(key, language: language)) · \(timestamp)\(model)")
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
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

    @ViewBuilder
    private var usageContent: some View {
        switch usageState {
        case .idle:
            Text("\(L10n.string("usage", language: language)) -")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(L10n.string("usage_unavailable", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .help(message)
        case let .loaded(usage), let .stale(usage, _):
            if showsFiveHourUsage {
                expandedUsageContent(usage)
            } else {
                compactWeeklyUsageContent(usage)
            }
        }
    }

    private func compactWeeklyUsageContent(_ usage: WeeklyUsage) -> some View {
        HStack(spacing: 7) {
            Text(L10n.string("usage", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if let message = usageState.refreshError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help(message)
                    .accessibilityLabel(message)
            }

            UsageBar(remainingPercent: usage.remainingPercent)
                .accessibilityLabel(L10n.string("usage", language: language))
                .accessibilityValue("\(usage.remainingPercent)\(L10n.string("left", language: language))")

            Text("\(usage.remainingPercent)\(L10n.string("left", language: language))")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func expandedUsageContent(_ usage: WeeklyUsage) -> some View {
        VStack(spacing: 8) {
            if let remaining = usage.fiveHourRemainingPercent,
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

    private func limitRow(
        title: String,
        remainingPercent: Int,
        resetsAt: Date
    ) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            UsageBar(remainingPercent: remainingPercent)
                .accessibilityLabel(title)
                .accessibilityValue("\(remainingPercent)\(L10n.string("left", language: language))")

            Text("\(remainingPercent)%")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 31, alignment: .trailing)

            Text(resetText(for: resetsAt))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var rowBackground: Color {
        if isActive {
            return Color(nsColor: .controlBackgroundColor).opacity(0.92)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.72 : 0.46)
    }

    private func resetText(for usage: WeeklyUsage) -> String {
        resetText(for: usage.resetsAt)
    }

    private func resetText(for resetsAt: Date) -> String {
        let date = BeijingDateTimeFormatter.string(from: resetsAt)
        return "\(L10n.string("resets", language: language)) \(date)"
    }
}

private struct UsageBar: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(width: 104, height: 4)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }
}
