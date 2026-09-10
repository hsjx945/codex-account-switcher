import AppKit
import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    let tokenActivity: TokenActivity?
    let tokenReportingDate: String?
    let tokenActivityRefreshFinished: Bool
    let showsTokenActivity: Bool
    let warmupStatus: WarmupRecord?
    var tokenRefreshError: String? = nil
    var tokenFetchedAt: Date? = nil
    var tokenRefreshPending: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            titleRow
            usageContent
                .help(usageState.refreshError ?? "")
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

            if usageState.isQuotaExhausted(showsFiveHour: shouldShowFiveHourUsage) {
                let message = "\(L10n.string("usage", language: language)) 0%"
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
                        foreground: activeTagPalette.foreground,
                        background: activeTagPalette.background
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
                .foregroundStyle(.primary)
        case let .unavailable(message):
            Text(L10n.string("usage_unavailable", language: language))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .help(message)
        case let .loaded(usage), let .stale(usage, _):
            VStack(spacing: 9) {
                if shouldShowFiveHourUsage,
                   let remaining = usage.fiveHourRemainingPercent {
                    limitRow(
                        title: L10n.string("five_hour", language: language),
                        remainingPercent: remaining,
                        resetsAt: usage.fiveHourResetsAt
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
        resetsAt: Date?
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)

            UsageBar(remainingPercent: remainingPercent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(title)
                .accessibilityValue("\(remainingPercent)\(L10n.string("left", language: language))")

            Text("\(remainingPercent)%")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 44, alignment: .trailing)

            Text(resetsAt.map(resetText(for:)) ?? L10n.string("reset_unknown", language: language))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
                .help("\(L10n.string("resets", language: language)) \(resetsAt.map(resetText(for:)) ?? "—") (UTC+8)")
        }
    }

    private func warmupContent(_ record: WarmupRecord) -> some View {
        let key = switch record.outcome {
        case .attempting: "warmup_attempting"
        case .confirmed: "warmup_confirmed"
        case .unconfirmed: "warmup_unconfirmed"
        case .failed: "warmup_failed"
        }
        return Text("\(L10n.string(key, language: language)) · \(BeijingDateTimeFormatter.string(from: record.attemptedAt, language: language))")
            .font(.system(size: 10.5))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var rowBackground: Color {
        if colorScheme == .dark {
            if isActive {
                return isHovering
                    ? Color(red: 0.225, green: 0.17, blue: 0.135)
                    : Color(red: 0.19, green: 0.145, blue: 0.12)
            }
            return isHovering
                ? Color(red: 0.205, green: 0.21, blue: 0.22)
                : Color(red: 0.155, green: 0.16, blue: 0.17)
        }
        if isActive {
            return isHovering
                ? Color(red: 1.0, green: 0.945, blue: 0.895)
                : Color(red: 1.0, green: 0.965, blue: 0.93)
        }
        return isHovering
            ? Color(red: 0.94, green: 0.945, blue: 0.955)
            : .white
    }

    private var shouldShowFiveHourUsage: Bool {
        showsFiveHourUsage && account.supportsFiveHourUsage
    }

    private var activeTagPalette: TagPalette {
        colorScheme == .dark
            ? TagPalette(
                foreground: Color(red: 0.84, green: 1.0, blue: 0.90),
                background: Color(red: 0.12, green: 0.34, blue: 0.22)
            )
            : TagPalette(
                foreground: Color(red: 0.05, green: 0.34, blue: 0.16),
                background: Color(red: 0.80, green: 0.94, blue: 0.85)
            )
    }

    private var planPalette: TagPalette {
        let isDark = colorScheme == .dark
        switch account.planType?.lowercased() {
        case "plus":
            return isDark
                ? TagPalette(foreground: Color(red: 1.0, green: 0.85, blue: 0.77), background: Color(red: 0.42, green: 0.17, blue: 0.08))
                : TagPalette(foreground: Color(red: 0.57, green: 0.20, blue: 0.05), background: Color(red: 1.0, green: 0.87, blue: 0.79))
        case "team":
            return isDark
                ? TagPalette(foreground: Color(red: 0.82, green: 0.91, blue: 1.0), background: Color(red: 0.13, green: 0.29, blue: 0.47))
                : TagPalette(foreground: Color(red: 0.11, green: 0.32, blue: 0.57), background: Color(red: 0.84, green: 0.91, blue: 1.0))
        case "prolite":
            return isDark
                ? TagPalette(foreground: Color(red: 0.92, green: 0.87, blue: 1.0), background: Color(red: 0.29, green: 0.18, blue: 0.49))
                : TagPalette(foreground: Color(red: 0.34, green: 0.18, blue: 0.57), background: Color(red: 0.90, green: 0.85, blue: 0.98))
        case "pro":
            return isDark
                ? TagPalette(foreground: Color(red: 1.0, green: 0.86, blue: 0.92), background: Color(red: 0.43, green: 0.17, blue: 0.28))
                : TagPalette(foreground: Color(red: 0.53, green: 0.17, blue: 0.32), background: Color(red: 0.97, green: 0.85, blue: 0.90))
        default:
            return isDark
                ? TagPalette(foreground: Color(red: 0.94, green: 0.95, blue: 0.93), background: Color(red: 0.27, green: 0.29, blue: 0.27))
                : TagPalette(foreground: Color(red: 0.26, green: 0.29, blue: 0.26), background: Color(red: 0.88, green: 0.90, blue: 0.87))
        }
    }

    private var planForeground: Color {
        planPalette.foreground
    }

    private var planBackground: Color {
        planPalette.background
    }

    private func resetText(for resetsAt: Date) -> String {
        BeijingDateTimeFormatter.string(from: resetsAt, language: language)
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
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct TagPalette {
    let foreground: Color
    let background: Color
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
