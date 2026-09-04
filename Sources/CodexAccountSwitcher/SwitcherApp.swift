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
                MenuBarLogo()

                if let accountLabel = model.activeAccountLabel {
                    Text(accountLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 150)
                }

                if model.settings.showsMenuBarPercentage,
                   let remainingPercent = model.activeRemainingPercent {
                    Text("· \(remainingPercent)%")
                        .monospacedDigit()
                }
            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(menuBarAccessibilityLabel)
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
        if let accountLabel = model.activeAccountLabel {
            parts.append(accountLabel)
        }
        if model.settings.showsMenuBarPercentage,
           let remainingPercent = model.activeRemainingPercent {
            parts.append("\(remainingPercent)%")
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
