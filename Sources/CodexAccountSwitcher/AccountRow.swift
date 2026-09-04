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
        HStack(alignment: .center, spacing: 10) {
            Text(account.initials)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.primaryLabel(style: nameStyle))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let secondary = account.secondaryLabel(style: nameStyle) {
                            Text(secondary)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                    if isActive {
                        Text(L10n.string("active", language: language))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color(red: 0.38, green: 0.43, blue: 0.49).opacity(0.14),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                            }
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
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func tokenContent(_ activity: TokenActivity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
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
        let timestamp = record.attemptedAt.formatted(
            .dateTime.month(.abbreviated).day().hour().minute()
        )
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
        VStack(spacing: 5) {
            if let remaining = usage.fiveHourRemainingPercent,
               let resetsAt = usage.fiveHourResetsAt {
                limitRow(
                    title: L10n.string("five_hour", language: language),
                    remainingPercent: remaining,
                    resetsAt: resetsAt,
                    includesDate: false
                )
            }
            limitRow(
                title: L10n.string("weekly", language: language),
                remainingPercent: usage.remainingPercent,
                resetsAt: usage.resetsAt,
                includesDate: true
            )
        }
    }

    private func limitRow(
        title: String,
        remainingPercent: Int,
        resetsAt: Date,
        includesDate: Bool
    ) -> some View {
        HStack(spacing: 7) {
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

            Text(resetText(for: resetsAt, includesDate: includesDate))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var rowBackground: Color {
        if isActive {
            return Color(red: 0.38, green: 0.43, blue: 0.49).opacity(0.13)
        }
        return Color.primary.opacity(isHovering ? 0.055 : 0)
    }

    private func resetText(for usage: WeeklyUsage) -> String {
        resetText(for: usage.resetsAt, includesDate: true)
    }

    private func resetText(for resetsAt: Date, includesDate: Bool) -> String {
        let date = includesDate
            ? resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : resetsAt.formatted(.dateTime.hour().minute())
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
        .frame(maxWidth: .infinity)
        .frame(height: 3)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }
}
