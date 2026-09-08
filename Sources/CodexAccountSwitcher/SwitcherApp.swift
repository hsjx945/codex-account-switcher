import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @NSApplicationDelegateAdaptor(SwitcherAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            HStack(spacing: 4) {
                if model.switchingAccount != nil {
                    ProgressView().controlSize(.mini)
                    Text(model.text("switching_title"))
                } else if model.switchedAccount != nil {
                    Image(systemName: "checkmark.circle.fill")
                    Text(model.text("switched_reopen_title"))
                } else {
                    MenuBarLogo()
                }

                if model.settings.showsMenuBarPercentage && model.switchingAccount == nil && model.switchedAccount == nil {
                    Text(model.menuBarQuota.title)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(menuBarAccessibilityLabel)
                .help(menuBarAccessibilityLabel)
                .task {
                    await model.start()
                    appDelegate.bindSwitchHandler { [weak model] profileID in
                        await model?.handleNotificationSwitchRequest(profileID: profileID)
                    }
                    await model.startBackgroundUsageRefresh()
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            QuitApplicationCommands(title: model.text("quit"))
        }
    }

    private var menuBarAccessibilityLabel: String {
        var parts = ["Codex Account Switcher"]
        if model.switchingAccount != nil { parts.append(model.text("switching_title")) }
        if model.switchedAccount != nil { parts.append(model.text("switched_reopen_title")) }
        if model.settings.showsMenuBarPercentage && model.switchingAccount == nil && model.switchedAccount == nil {
            parts.append(model.activeShowsFiveHour ? model.text("five_hour") + " / " + model.text("weekly") : model.text("weekly"))
            parts.append(model.menuBarQuota.title)
            if model.menuBarQuota.isStale {
                parts.append(model.text("usage_cached"))
            }
        }
        return parts.joined(separator: ", ")
    }
}

private struct MenuBarLogo: View {
    private static let logicalSize = NSSize(width: 17.5, height: 17.5)

    private static let image: NSImage = {
        let resourceBundleName = "CodexAccountSwitcher_CodexAccountSwitcher.bundle"
        let resourceBundle = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0 }
            .map { $0.appending(path: resourceBundleName) }
            .compactMap { Bundle(url: $0) }
            .first
        guard let url = resourceBundle?.url(
            forResource: "account-switcher-logo",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing account-switcher-logo.png")
        }
        image.size = logicalSize
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .frame(width: 17.5, height: 17.5)
            .accessibilityHidden(true)
    }
}

private struct QuitApplicationCommands: Commands {
    let title: String

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(title) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
