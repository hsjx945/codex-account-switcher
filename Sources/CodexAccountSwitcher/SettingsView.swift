import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: model.text("settings"),
                backTitle: model.text("back"),
                onBack: onBack
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    generalSection
                    usageSection
                    experimentalSection
                }
                .padding(14)
            }
            .frame(maxHeight: 560)
        }
        .onAppear { model.refreshLaunchAtLoginStatus() }
    }

    private var generalSection: some View {
        SettingsSection(title: model.text("general")) {
            VStack(spacing: 0) {
                SettingToggleRow(
                    title: model.text("launch_at_login"),
                    detail: launchAtLoginDetail,
                    detailColor: launchAtLoginDetail == nil ? .secondary : .orange,
                    isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )

                if model.launchAtLoginRequiresApproval {
                    Button(model.text("open_system_settings")) {
                        model.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingDivider()

                SettingToggleRow(
                    title: model.text("show_menu_bar_percentage"),
                    isOn: Binding(
                        get: { model.settings.showsMenuBarPercentage },
                        set: { enabled in Task { await model.setShowsMenuBarPercentage(enabled) } }
                    )
                )

                SettingDivider()

                SettingToggleRow(
                    title: model.text("show_supported_five_hour_usage"),
                    isOn: Binding(
                        get: { model.settings.showsFiveHourUsage },
                        set: { enabled in Task { await model.setShowsFiveHourUsage(enabled) } }
                    )
                )

                SettingDivider()

                HStack {
                    Text(model.text("language"))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Picker(model.text("language"), selection: Binding(
                        get: { model.settings.language },
                        set: { language in Task { await model.setLanguage(language) } }
                    )) {
                        Text(model.text("system_default")).tag(AppLanguage.system)
                        Text(model.text("english")).tag(AppLanguage.english)
                        Text(model.text("simplified_chinese")).tag(AppLanguage.simplifiedChinese)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 50)
            }
        }
    }

    private var usageSection: some View {
        SettingsSection(title: model.text("usage_and_alerts")) {
            VStack(spacing: 0) {
                SettingToggleRow(
                    title: model.text("show_token_activity"),
                    detail: model.text("show_token_activity_hint"),
                    isOn: Binding(
                        get: { model.settings.showsTokenActivity },
                        set: { enabled in Task { await model.setShowsTokenActivity(enabled) } }
                    )
                )

                SettingDivider()

                SettingToggleRow(
                    title: model.text("five_hour_reset_notifications"),
                    detail: model.text("five_hour_reset_notifications_hint"),
                    isOn: Binding(
                        get: { model.settings.fiveHourResetNotificationsEnabled },
                        set: { enabled in
                            Task { await model.setFiveHourResetNotificationsEnabled(enabled) }
                        }
                    )
                )
            }
        }
    }

    private var experimentalSection: some View {
        SettingsSection(title: model.text("experimental")) {
            VStack(spacing: 0) {
                SettingToggleRow(
                    title: model.text("automatic_warmup"),
                    detail: model.text("warmup_hint"),
                    isOn: Binding(
                        get: { model.settings.automaticWarmupEnabled },
                        set: { enabled in Task { await model.setAutomaticWarmupEnabled(enabled) } }
                    )
                )

                if model.settings.automaticWarmupEnabled {
                    SettingDivider()

                    HStack {
                        Text(model.text("warmup_time"))
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        DatePicker(
                            model.text("warmup_time"),
                            selection: Binding(
                                get: { model.warmupTime },
                                set: { date in Task { await model.setWarmupTime(date) } }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 50)
                }
            }
        }
    }

    private var launchAtLoginDetail: String? {
        if model.launchAtLoginRequiresApproval {
            return model.text("launch_at_login_requires_approval")
        }
        if model.launchAtLoginUnavailable {
            return model.text("launch_at_login_unavailable")
        }
        return nil
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.7)
                .padding(.leading, 4)

            content
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.56),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct SettingToggleRow: View {
    let title: String
    var detail: String? = nil
    var detailColor: Color = .secondary
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 50)
    }
}

private struct SettingDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}
