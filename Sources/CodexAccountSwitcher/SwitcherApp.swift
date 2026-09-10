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
