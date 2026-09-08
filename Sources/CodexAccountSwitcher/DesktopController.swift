import AppKit
import Foundation
import ApplicationServices

enum DesktopControllerError: LocalizedError, Sendable {
    case applicationNotFound
    case quitRequestFailed
    case forceQuitFailed
    case didNotExit
    case readinessPermissionRequired
    case reopenFailed

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "The Codex Desktop application could not be found."
        case .quitRequestFailed:
            "Codex Desktop rejected the quit request."
        case .forceQuitFailed:
            "Codex Desktop rejected the force-quit request."
        case .didNotExit:
            "Codex Desktop did not exit within 15 seconds after the force-quit request."
        case .readinessPermissionRequired:
            "账号身份已切换，但尚无法验证 Codex 界面就绪。请在系统设置 → 隐私与安全性 → 辅助功能中允许 Codex Account Switcher 读取界面。"
        case .reopenFailed:
            "Codex Desktop could not be reopened. Open it manually to continue."
        }
    }
}

struct DesktopController: DesktopControlling {
    private let bundleIdentifiers = ["com.openai.codex"]
    private let applicationPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]

    func isDesktopRunning() async -> Bool {
        desktopRunning
    }

    func closeDesktop() async throws {
        let running = NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
        guard !running.isEmpty else { return }
        for application in running where !application.isTerminated {
            let processIdentifier = application.processIdentifier
            guard application.terminate() || !isDesktopRunning(processIdentifier: processIdentifier) else {
                throw DesktopControllerError.quitRequestFailed
            }
        }

        let clock = ContinuousClock()
        let gracefulDeadline = clock.now.advanced(by: .seconds(2))
        while clock.now < gracefulDeadline {
            if !desktopRunning { return }
            try await Task.sleep(for: .milliseconds(100))
        }

        for application in runningDesktopApplications where !application.isTerminated {
            let processIdentifier = application.processIdentifier
            guard application.forceTerminate()
                    || !isDesktopRunning(processIdentifier: processIdentifier)
            else {
                throw DesktopControllerError.forceQuitFailed
            }
        }

        let deadline = clock.now.advanced(by: .seconds(15))
        while clock.now < deadline {
            if !desktopRunning { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DesktopControllerError.didNotExit
    }

    func reopenDesktop() async throws {
        guard let url = applicationURL() else {
            throw DesktopControllerError.applicationNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            guard AXIsProcessTrusted() else { throw DesktopControllerError.readinessPermissionRequired }
            try await waitForDesktopWindow(timeout: .seconds(60)) {
                guard !application.isTerminated, application.isFinishedLaunching else { return false }
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                return windows.contains { window in
                    guard (window[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier,
                          (window[kCGWindowLayer as String] as? Int) == 0,
                          let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let width = bounds["Width"] as? Double,
                          let height = bounds["Height"] as? Double else { return false }
                    return width > 200 && height > 150 && desktopHasUsableContent(pid: application.processIdentifier)
                }
            }
        } catch let error as DesktopControllerError {
            throw error
        } catch {
            throw DesktopControllerError.reopenFailed
        }
    }

    private func applicationURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return applicationPaths
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private var desktopRunning: Bool {
        !runningDesktopApplications.isEmpty
    }

    private var runningDesktopApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
    }

    private func isDesktopRunning(processIdentifier: pid_t) -> Bool {
        runningDesktopApplications.contains { $0.processIdentifier == processIdentifier }
    }
}

// Opening a process is not the same as showing its desktop window.
func waitForDesktopWindow(
    timeout: Duration = .seconds(30),
    isReady: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var readySince: ContinuousClock.Instant?
    while ContinuousClock.now < deadline {
        try Task.checkCancellation()
        if isReady() {
            if let readySince, readySince.duration(to: .now) >= .milliseconds(500) { return }
            if readySince == nil { readySince = .now }
        } else { readySince = nil }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw DesktopControllerError.reopenFailed
}

// A visible Electron shell is insufficient: require a rendered editor or
// a recognized task action in its accessibility tree, not a splash window.
func desktopHasUsableContent(pid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
          let roots = windows as? [AXUIElement] else { return false }
    var queue = roots.map { ($0, 0) }
    var visited = 0
    while let (element, depth) = queue.popLast(), visited < 400 {
        visited += 1
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        if role == kAXTextAreaRole as String { return true }
        if role == kAXButtonRole as String {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            if ["New task", "New chat", "新任务", "新建任务", "新对话"].contains(title as? String ?? "") { return true }
        }
        guard depth < 18 else { continue }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let values = children as? [AXUIElement] {
            queue.append(contentsOf: values.map { ($0, depth + 1) })
        }
    }
    return false
}
