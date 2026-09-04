import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    let nameStyle: AccountNameStyle
    let tokenActivity: TokenActivity?
    let localModelUsage: LocalModelUsageSummary?
    let showsTokenActivity: Bool
    let warmupStatus: WarmupRecord?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.primaryLabel(style: nameStyle))
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let secondary = account.secondaryLabel(style: nameStyle) {
                        Text(secondary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                if isActive {
                    Text(L10n.string("active", language: language))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 42, height: 22)
                        .background(Color.accentColor.opacity(0.13), in: Capsule())
                }
                if let badge = account.subscriptionBadge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .frame(width: 62, height: 22)
                        .background(Color.primary.opacity(0.075), in: Capsule())
                }
                if let message = usageState.refreshError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(message)
                        .accessibilityLabel(message)
                }
            }

            usageContent

            if showsTokenActivity {
                if isActive {
                    if let localModelUsage {
                        localTokenContent(localModelUsage, serverActivity: tokenActivity)
                    } else {
                        Label(L10n.string("token_scanning", language: language), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let tokenActivity {
                    tokenContent(tokenActivity)
                }
            }

            if let warmupStatus {
                warmupContent(warmupStatus)
            }
        }
        .frame(minHeight: 72)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.06),
                    lineWidth: isActive ? 1 : 0.75
                )
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func tokenContent(_ activity: TokenActivity) -> some View {
        HStack(spacing: 16) {
            tokenMetric("sun.max", "today", activity.tokensForToday())
            tokenMetric("calendar", "last_7_days", activity.tokensIfCovered(inLastDays: 7))
            tokenMetric("calendar.badge.clock", "last_30_days", activity.tokensIfCovered(inLastDays: 30))
        }
    }

    private func localTokenContent(
        _ summary: LocalModelUsageSummary,
        serverActivity: TokenActivity?
    ) -> some View {
        let today = summary.models.reduce(0) { $0 + $1.todayTokens }
        let seven = serverActivity?.tokensIfCovered(inLastDays: 7)
        let thirty = serverActivity?.tokensIfCovered(inLastDays: 30)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 16) {
                tokenMetric("sun.max.fill", "today", today)
                tokenMetric("calendar", "last_7_days", seven)
                tokenMetric("calendar.badge.clock", "last_30_days", thirty)
            }
            if !summary.models.isEmpty {
                Label(
                    summary.models.prefix(3).map { "\($0.model) \(formatTokens($0.todayTokens))" }.joined(separator: " · "),
                    systemImage: "cpu"
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .help(L10n.string("local_models_hint", language: language))
    }

    private func tokenMetric(_ systemImage: String, _ key: String, _ tokens: Int?) -> some View {
        Label(
            "\(L10n.string(key, language: language)) \(tokens.map(formatTokens) ?? "—")",
            systemImage: systemImage
        )
            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
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
            .font(.system(size: 11))
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
            if shouldShowFiveHourUsage {
                expandedUsageContent(usage)
            } else {
                compactWeeklyUsageContent(usage)
            }
        }
    }

    private func compactWeeklyUsageContent(_ usage: WeeklyUsage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityLabel(L10n.string("weekly", language: language))

            if let message = usageState.refreshError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(message)
                    .accessibilityLabel(message)
            }

            UsageBar(remainingPercent: usage.remainingPercent)
                .accessibilityLabel(L10n.string("usage", language: language))
                .accessibilityValue("\(usage.remainingPercent)\(L10n.string("left", language: language))")

            Text("\(usage.remainingPercent)\(L10n.string("left", language: language))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)

            Text(resetText(for: usage))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func expandedUsageContent(_ usage: WeeklyUsage) -> some View {
        VStack(spacing: 8) {
            if let remaining = usage.fiveHourRemainingPercent,
               let resetsAt = usage.fiveHourResetsAt {
                limitRow(
                    systemImage: "clock",
                    accessibilityTitle: L10n.string("five_hour", language: language),
                    remainingPercent: remaining,
                    resetsAt: resetsAt
                )
            }
            limitRow(
                systemImage: "calendar",
                accessibilityTitle: L10n.string("weekly", language: language),
                remainingPercent: usage.remainingPercent,
                resetsAt: usage.resetsAt
            )
        }
    }

    private func limitRow(
        systemImage: String,
        accessibilityTitle: String,
        remainingPercent: Int,
        resetsAt: Date
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityLabel(accessibilityTitle)

            UsageBar(remainingPercent: remainingPercent)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue("\(remainingPercent)\(L10n.string("left", language: language))")

            Text("\(remainingPercent)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Text(resetText(for: resetsAt))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var rowBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.15)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.70 : 0.38)
    }

    private var shouldShowFiveHourUsage: Bool {
        showsFiveHourUsage && account.supportsFiveHourUsage
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
        .frame(width: 120, height: 5)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }
}
