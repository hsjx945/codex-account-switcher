import AppKit
import Combine
import SwiftUI

@MainActor
final class SwitcherPopoverController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var wasSwitching = false

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(model: model))
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        let bundleURL = Bundle.main.resourceURL?.appending(path: "CodexAccountSwitcher_CodexAccountSwitcher.bundle")
        let resource = bundleURL.flatMap(Bundle.init(url:))?.url(forResource: "account-switcher-logo", withExtension: "png")
        let logo = resource.flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Codex Account Switcher")
        logo?.size = NSSize(width: 17.5, height: 17.5)
        logo?.isTemplate = true
        item.button?.image = logo
        observation = model.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.update() }
        }
        update()
    }

    private func update() {
        item.button?.title = model.settings.showsMenuBarPercentage ? " " + model.menuBarQuota.title : ""
        let switching = model.switchingAccount != nil
        // applicationDefined prevents deactivation/outside clicks from closing
        // the progress panel when Codex exits and activates again.
        popover.behavior = switching ? .applicationDefined : .transient
        if switching {
            show()
            popover.contentViewController?.view.window?.level = .floating
        } else if wasSwitching {
            popover.contentViewController?.view.window?.level = .floating
            show()
        }
        wasSwitching = switching
    }

    @objc private func toggle() {
        if popover.isShown {
            if model.switchingAccount == nil { popover.performClose(nil) }
        } else { show() }
    }

    func show() {
        guard !popover.isShown, let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        model.switchingAccount == nil
    }

    func popoverDidClose(_ notification: Notification) {
        model.dismissSwitchResult()
    }
}
