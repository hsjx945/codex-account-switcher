import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: PopoverPage = .accounts

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.visibleError {
                InlineErrorBanner(
                    title: model.text(error.titleKey),
                    message: error.messageKey.map(model.text) ?? error.message,
                    dismissTitle: model.text("ok"),
                    onDismiss: model.dismissError
                )
            }

            switch page {
            case .accounts:
                accountPage
            case .manageAccounts:
                ManageAccountsView(model: model) {
                    page = .accounts
                }
            case .settings:
                SettingsView(model: model) {
                    page = .accounts
                }
            case let .confirmSwitch(account):
                SwitchConfirmationPage(
                    model: model,
                    account: account,
                    onCancel: { page = .accounts },
                    onConfirm: { switchAccount(account) }
                )
            case let .switching(account):
                SwitchingPage(model: model, account: account)
            }
        }
        .frame(width: 420)
        .background(popoverBackground)
        .onAppear { page = .accounts }
        .task {
            await model.start()
            model.refreshWeeklyUsage()
        }
    }

    private var popoverBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.11, blue: 0.12)
            : Color(red: 0.965, green: 0.968, blue: 0.972)
    }

    private var accountPage: some View {
        VStack(spacing: 0) {
            switch model.activeIdentityState {
            case .checking, .confirmed:
                EmptyView()
            case .unavailable:
                // A successful account/read response can legitimately contain no
                // identity. That is not evidence of a mismatch, so keep the list
                // quiet and reserve the warning banner for an actionable conflict.
                EmptyView()
            case .mismatch:
                IdentityStatusBanner(
                    title: model.text("identity_mismatch"),
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    color: .red,
                    retryTitle: model.text("retry"),
                    onRetry: model.retryActiveIdentityConfirmation
                )
            }

            if model.accounts.isEmpty {
                ContentUnavailableView(
                    model.text("no_accounts"),
                    systemImage: "person.crop.circle.badge.plus"
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                if model.displayedAccounts.count <= 4 {
                    accountRows
                        .padding(9)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        accountRows.padding(9)
                    }
                    .frame(height: 520)
                }
            }

            if model.settings.showsTokenActivity, !model.accounts.isEmpty {
                TokenTotalRow(
                    title: tokenTotalTitle,
                    tokens: model.reportedTokenTotal,
                    unavailableTitle: model.text("token_unavailable_short")
                )
            }

            Divider()

            HStack(spacing: 5) {
                FooterAction(title: model.text("manage"), systemImage: "person.2") {
                    page = .manageAccounts
                }
                .disabled(model.isMutating)

                FooterAction(title: model.text("settings"), systemImage: "gearshape") {
                    page = .settings
                }
                .disabled(model.isMutating)

                FooterAction(
                    title: model.text("quit"),
                    systemImage: "power",
                    shortcut: KeyboardShortcut("q", modifiers: .command),
                    iconOnly: true
                ) {
                    NSApp.terminate(nil)
                }
                .frame(width: 42)
            }
            .padding(8)
        }
    }

    private var accountRows: some View {
        VStack(spacing: 8) {
            ForEach(model.displayedAccounts) { account in
                Button {
                    if account.id == model.activeAccountID {
                        NSApp.keyWindow?.close()
                    } else {
                        page = .confirmSwitch(account)
                    }
                } label: {
                    AccountRow(
                        account: account,
                        usageState: model.usageStates[account.id] ?? .idle,
                        isActive: account.id == model.activeAccountID,
                        language: model.settings.language,
                        showsFiveHourUsage: model.settings.showsFiveHourUsage,
                        tokenActivity: model.tokenActivities[account.id],
                        tokenReportingDate: model.tokenReportingDate,
                        tokenActivityRefreshFinished: model.tokenActivityRefreshFinished,
                        showsTokenActivity: model.settings.showsTokenActivity,
                        warmupStatus: model.warmupStatuses[account.id]
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isMutating)
            }
        }
    }

    private func switchAccount(_ account: AccountProfile) {
        page = .switching(account)
        Task {
            await model.switchAccount(to: account.id)
            page = .accounts
        }
    }

    private var tokenTotalTitle: String {
        guard let dateKey = model.tokenReportingDate else {
            return model.text("total_token_today")
        }
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return model.format("dated_token_total", dateKey)
        }
        let usesChinese = model.settings.language == .simplifiedChinese
            || (model.settings.language == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
        let displayDate = usesChinese ? "\(month)月\(day)日" : "\(month)/\(day)"
        let today = BeijingDateTimeFormatter.calendar.dateComponents([.year, .month, .day], from: Date())
        if today.month == month, today.day == day,
           Int(parts[0]) == today.year {
            return model.text("total_token_today")
        }
        return model.format("dated_token_total", displayDate)
    }
}

private struct TokenTotalRow: View {
    let title: String
    let tokens: Int?
    let unavailableTitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Text(tokens.map(formatTokens) ?? unavailableTitle)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(totalBackground)
    }

    private var totalBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.155, green: 0.16, blue: 0.17)
            : .white
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

private enum PopoverPage {
    case accounts
    case manageAccounts
    case settings
    case confirmSwitch(AccountProfile)
    case switching(AccountProfile)
}

private struct IdentityStatusBanner: View {
    let title: String
    let systemImage: String
    let color: Color
    let retryTitle: String
    let onRetry: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(2)

            Spacer(minLength: 6)

            Button(retryTitle, action: onRetry)
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(bannerBackground)
    }

    private var bannerBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.105, blue: 0.115)
            : Color(red: 1.0, green: 0.90, blue: 0.90)
    }
}

private struct SwitchConfirmationPage: View {
    @ObservedObject var model: AppModel
    let account: AccountProfile
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: model.text("confirm_switch"),
                backTitle: model.text("back"),
                onBack: onCancel
            )

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                Text(model.format("switch_title", account.preferredLabel))
                    .font(.system(size: 18, weight: .bold))

                Text(model.text("switch_body"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    ImpactRow(text: model.text("switch_impact_desktop"))
                    ImpactRow(text: model.text("switch_impact_existing_cli"))
                    ImpactRow(text: model.text("switch_impact_new_cli"))
                }

                HStack(spacing: 8) {
                    Button(model.text("cancel"), action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button(model.text("switch"), action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
    }
}

private struct ImpactRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SwitchingPage: View {
    @ObservedObject var model: AppModel
    let account: AccountProfile

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.orange)

            VStack(spacing: 6) {
                Text(model.text("switching_title"))
                    .font(.system(size: 15, weight: .bold))
                Text(account.preferredLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(24)
    }
}

private struct InlineErrorBanner: View {
    let title: String
    let message: String
    let dismissTitle: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dismissTitle)
            .help(dismissTitle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
}

private struct FooterAction: View {
    let title: String
    let systemImage: String
    var shortcut: KeyboardShortcut?
    var iconOnly = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Image(systemName: systemImage)
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .background(
            Color.primary.opacity(isHovering ? 0.06 : 0),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .help(title)
    }
}
