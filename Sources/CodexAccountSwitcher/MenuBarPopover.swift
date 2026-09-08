import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var model: AppModel
    var initiallyExpandsLocalModels = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: PopoverPage = .accounts
    @State private var pendingSwitch: AccountProfile?

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

            if let account = model.switchingAccount {
                SwitchingPage(model: model, account: account)
            } else if let account = model.switchedAccount {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42)).foregroundStyle(.green)
                    Text(model.text("switched_reopen_title")).font(.headline)
                    Text(account.preferredLabel).font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(24)
            } else if let account = pendingSwitch {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.format("switch_title", account.preferredLabel))
                        .font(.headline)
                    Text(model.text("switch_body"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.text("cancel")) { pendingSwitch = nil }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(model.text("confirm_switch")) {
                            pendingSwitch = nil
                            switchAccount(account)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("confirm-account-switch")
                    }
                }
                .padding(24)
            } else {
                switch page {
                case .accounts:
                    accountPage
                case .manageAccounts:
                    ManageAccountsView(model: model) { page = .accounts }
                case .settings:
                    SettingsView(model: model) { page = .accounts }
                }
            }
        }
        .onChange(of: model.switchingAccount?.id) { _, _ in page = .accounts }
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
                // MenuBarExtra measures its content before assigning a height.
                // ViewThatFits can choose a zero-height ScrollView in that pass.
                // Small lists keep their intrinsic height; larger lists always
                // receive an explicit, scrollable viewport.
                if model.displayedAccounts.count <= 2 {
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

            if model.settings.showsTokenActivity {
                TokenTotalRow(
                    title: model.text("token_today_consumed"),
                    usage: model.localTokenSnapshot?.usage,
                    models: model.localTokenSnapshot?.models ?? [],
                    language: model.settings.language,
                    statusText: localTokenStatusText,
                    detailText: model.text("token_total_local_hint"),
                    isRefreshing: model.localTokenSnapshot == nil,
                    initiallyExpanded: initiallyExpandsLocalModels
                )
            }

            Divider()

            HStack(spacing: 5) {
                FooterAction(title: model.text("manage"), systemImage: "person.2") {
                    page = .manageAccounts
                }
                .disabled(model.isMutating || model.isAddingAccount)

                FooterAction(title: model.text("settings"), systemImage: "gearshape") {
                    page = .settings
                }
                .disabled(model.isMutating || model.isAddingAccount)

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

    private var localTokenStatusText: String {
        guard let snapshot = model.localTokenSnapshot else { return model.text("token_scanning") }
        switch snapshot.state {
        case .idle, .monitoring:
            guard let latest = snapshot.latestEventAt else { return model.text("token_local_no_events_today") }
            return String(format: model.text("token_local_last_event"), BeijingDateTimeFormatter.stringWithSeconds(from: latest, language: model.settings.language))
        case let .failed(message):
            return String(format: model.text("token_local_failed"), message)
        }
    }

    private var accountRows: some View {
        VStack(spacing: 8) {
            ForEach(model.displayedAccounts) { account in
                Button {
                    if account.id != model.activeAccountID {
                        pendingSwitch = account
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
                        warmupStatus: model.warmupStatuses[account.id],
                        tokenRefreshError: model.tokenRefreshErrors[account.id],
                        tokenFetchedAt: model.tokenFetchedAt[account.id],
                        tokenRefreshPending: model.tokenRefreshPending.contains(account.id)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isMutating || model.isAddingAccount)
            }
        }
    }

    private func switchAccount(_ account: AccountProfile) {
        Task { await model.switchAccount(to: account.id) }
    }

}

struct TokenTotalRow: View {
    let title: String
    let usage: LocalTokenComponents?
    let models: [LocalModelTokenUsage]
    let language: AppLanguage
    let statusText: String
    let detailText: String
    let isRefreshing: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var modelsExpanded: Bool
    @State private var hoverTask: Task<Void, Never>?

    init(
        title: String,
        usage: LocalTokenComponents?,
        models: [LocalModelTokenUsage],
        language: AppLanguage,
        statusText: String,
        detailText: String,
        isRefreshing: Bool,
        initiallyExpanded: Bool = false
    ) {
        self.title = title
        self.usage = usage
        self.models = models
        self.language = language
        self.statusText = statusText
        self.detailText = detailText
        self.isRefreshing = isRefreshing
        _modelsExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        HStack(spacing: 10) {
            summaryTile(
                label: title,
                value: usage.map { TokenAmountFormatter.compact($0.total) } ?? "—",
                color: .blue
            )
            summaryTile(
                label: L10n.string(hasUnpricedUsage ? "api_partial_value" : "api_estimated_value", language: language),
                value: APITokenValuation.dollars(APITokenValuation.subtotal(models)),
                color: .orange
            )
            if isRefreshing { ProgressView().controlSize(.mini) }
        }
        .padding(12)
        .background(totalBackground)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard !Task.isCancelled else { return }
                    modelsExpanded = true
                }
            } else {
                modelsExpanded = false
                hoverTask = nil
            }
        }
        .onDisappear {
            hoverTask?.cancel()
            hoverTask = nil
            modelsExpanded = false
        }
        .onTapGesture { modelsExpanded.toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { modelsExpanded.toggle() }
        .popover(isPresented: $modelsExpanded, arrowEdge: .trailing) {
            details
        }
    }

    private func summaryTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.18)))
    }

    private var hasUnpricedUsage: Bool {
        models.contains { APITokenValuation.estimate($0) == nil }
    }

    var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 17, weight: .bold))
                Spacer()
                Text(usage.map { $0.total.formatted() } ?? "—")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
            }
            HStack(spacing: 10) {
                component(L10n.string("local_token_uncached_input", language: language), usage?.uncachedInput)
                component(L10n.string("local_token_cached_read", language: language), usage?.cachedInput)
                component(L10n.string("local_token_output", language: language), usage?.output)
            }
            Divider()
            HStack {
                Text(L10n.string("local_token_models", language: language))
                Spacer()
                Text("Token").frame(width: 65, alignment: .trailing)
                Text(L10n.string("api_value", language: language)).frame(width: 105, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold))
            if models.count > 6 {
                ScrollView { modelRows }.frame(height: 190)
            } else { modelRows }
            Divider()
            HStack {
                Text(L10n.string(hasUnpricedUsage ? "api_subtotal" : "api_total", language: language))
                Spacer()
                Text(APITokenValuation.dollars(APITokenValuation.subtotal(models))).monospacedDigit()
            }
            .font(.system(size: 15, weight: .semibold))
            Text(L10n.string("api_estimate_note", language: language))
                .font(.system(size: 11))
                .help(L10n.string("api_estimate_detail", language: language))
            Text(statusText).font(.system(size: 11))
        }
        .foregroundStyle(.primary)
        .padding(18)
        .frame(width: 440)
    }

    private var modelRows: some View {
        VStack(spacing: 9) {
            ForEach(models) { item in
                HStack(spacing: 8) {
                    Text(item.model ?? L10n.string("local_token_unknown_model", language: language))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.model ?? "")
                    Spacer(minLength: 0)
                    Text(formatTokens(item.usage.total))
                        .monospacedDigit()
                        .frame(width: 65, alignment: .trailing)
                    Text(APITokenValuation.estimate(item).map { APITokenValuation.dollars($0) }
                         ?? L10n.string("api_unpriced", language: language))
                        .monospacedDigit()
                        .frame(width: 105, alignment: .trailing)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            }
        }
    }

    private var totalBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.155, green: 0.16, blue: 0.17)
            : .white
    }

    private func formatTokens(_ tokens: Int) -> String {
        TokenAmountFormatter.compact(tokens)
    }

    private func component(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).lineLimit(1).minimumScaleFactor(0.85)
            Text(value.map(formatTokens) ?? "—").fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PopoverPage {
    case accounts
    case manageAccounts
    case settings
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

struct SwitchingPage: View {
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
