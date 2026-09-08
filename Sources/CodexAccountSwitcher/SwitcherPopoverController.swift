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
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var explicitDismissal = false

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(model: model))
        popover.behavior = .applicationDefined
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
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissFromOutsideClick() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.popover.contentViewController?.view.window,
                   event.window !== self.item.button?.window {
                    self.dismissFromOutsideClick()
                }
            }
            return event
        }
        update()
    }

    private func dismissFromOutsideClick() {
        guard popover.isShown, model.switchingAccount == nil else { return }
        explicitDismissal = true
        popover.performClose(nil)
    }

    private func update() {
        item.button?.title = model.settings.showsMenuBarPercentage ? " " + model.menuBarQuota.title : ""
        let switching = model.switchingAccount != nil
        // applicationDefined prevents deactivation/outside clicks from closing
        // the progress panel when Codex exits and activates again.
        popover.behavior = .applicationDefined
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
            if model.switchingAccount == nil { dismissFromOutsideClick() }
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
        if explicitDismissal {
            explicitDismissal = false
            model.dismissSwitchResult()
        } else if model.switchingAccount != nil || model.switchedAccount != nil {
            // A system-driven close must not consume the pending result.
            Task { @MainActor [weak self] in self?.show() }
        }
    }
}
