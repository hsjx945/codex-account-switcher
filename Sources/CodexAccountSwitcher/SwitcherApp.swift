import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @NSApplicationDelegateAdaptor(StatusBootstrap.self) private var statusBootstrap

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Codex Account Switcher") { statusBootstrap.controller?.show() }
            }
        }
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

@MainActor
final class StatusBootstrap: NSObject, NSApplicationDelegate {
    var controller: SwitcherPopoverController?
    let notificationDelegate = SwitcherAppDelegate()
    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationDelegate.applicationWillFinishLaunching(notification)
        let model = AppModel.live()
        controller = SwitcherPopoverController(model: model)
        notificationDelegate.bindSwitchHandler { [weak model] id in
            await model?.handleNotificationSwitchRequest(profileID: id)
        }
        Task { await model.startBackgroundUsageRefresh() }
    }
}
