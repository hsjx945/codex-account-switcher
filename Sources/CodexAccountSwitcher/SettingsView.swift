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
                VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("launch_at_login"))
                        if model.launchAtLoginRequiresApproval {
                            Text(model.text("launch_at_login_requires_approval"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if model.launchAtLoginUnavailable {
                            Text(model.text("launch_at_login_unavailable"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("launch_at_login")))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)

                if model.launchAtLoginRequiresApproval {
                    Button(model.text("open_system_settings")) {
                        model.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("show_menu_bar_percentage"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsMenuBarPercentage },
                        set: { enabled in Task { await model.setShowsMenuBarPercentage(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("show_menu_bar_percentage")))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("show_five_hour_usage"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsFiveHourUsage },
                        set: { enabled in Task { await model.setShowsFiveHourUsage(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("show_five_hour_usage")))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("account_name_style"))
                    Spacer()
                    Picker(model.text("account_name_style"), selection: Binding(
                        get: { model.settings.accountNameStyle },
                        set: { style in Task { await model.setAccountNameStyle(style) } }
                    )) {
                        Text(model.text("show_email")).tag(AccountNameStyle.email)
                        Text(model.text("show_nickname")).tag(AccountNameStyle.nickname)
                        Text(model.text("show_nickname_and_email")).tag(AccountNameStyle.nicknameAndEmail)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("show_token_activity"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsTokenActivity },
                        set: { enabled in Task { await model.setShowsTokenActivity(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("show_token_activity")))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.text("five_hour_reset_notifications"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.settings.fiveHourResetNotificationsEnabled },
                            set: { enabled in
                                Task { await model.setFiveHourResetNotificationsEnabled(enabled) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .fixedSize()
                        .accessibilityLabel(Text(model.text("five_hour_reset_notifications")))
                    }
                    Text(model.text("five_hour_reset_notifications_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)

                Divider()
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.text("automatic_warmup"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.settings.automaticWarmupEnabled },
                            set: { enabled in Task { await model.setAutomaticWarmupEnabled(enabled) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .fixedSize()
                        .accessibilityLabel(Text(model.text("automatic_warmup")))
                    }

                    if model.settings.automaticWarmupEnabled {
                        HStack {
                            Text(model.text("warmup_time"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                        Text(model.text("warmup_hint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("language"))
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
                .padding(.horizontal, 14)
                .frame(height: 44)
                }
            }
            .frame(maxHeight: 520)
        }
        .onAppear {
            model.refreshLaunchAtLoginStatus()
        }
    }
}
