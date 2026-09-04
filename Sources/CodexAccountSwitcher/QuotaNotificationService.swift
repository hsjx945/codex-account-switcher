import AppKit
import Foundation
import UserNotifications

/// Stable identifiers shared by notification delivery and action routing.
///
/// The profile UUID is the only value used to route an action. The account label
/// is presentation-only and must never be used as an account identity.
enum QuotaNotificationConstants {
    static let categoryIdentifier = "codex-account-switcher.quota-reset"
    static let switchActionIdentifier = "codex-account-switcher.switch-to-account"
    static let profileIDUserInfoKey = "profile_id"

    static func requestIdentifier(profileID: UUID, resetAt: Date) -> String {
        categoryIdentifier + "." + profileID.uuidString + "." + String(resetAt.timeIntervalSince1970)
    }
}

struct QuotaResetNotification: Equatable, Sendable {
    let profileID: UUID
    let accountLabel: String
    let title: String
    let body: String
    let resetAt: Date

    init(
        profileID: UUID,
        accountLabel: String,
        title: String,
        body: String,
        resetAt: Date
    ) {
        self.profileID = profileID
        self.accountLabel = accountLabel
        self.title = title
        self.body = body
        self.resetAt = resetAt
    }
}

/// UserNotifications supplies a completion block from an Objective-C callback.
/// Keep the single invocation explicit when the action is handled on the main
/// actor, instead of silently acknowledging the action before it is dispatched.
private final class NotificationCompletionHandler: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        handler()
    }
}

protocol QuotaNotificationServicing: AnyObject, Sendable {
    func requestAuthorization() async throws -> Bool
    func sendFiveHourResetNotification(
        profileID: UUID,
        accountLabel: String,
        title: String,
        body: String,
        resetAt: Date
    ) async throws
}

actor InertQuotaNotificationService: QuotaNotificationServicing {
    func requestAuthorization() async throws -> Bool { false }

    func sendFiveHourResetNotification(
        profileID: UUID,
        accountLabel: String,
        title: String,
        body: String,
        resetAt: Date
    ) async throws {}
}

@MainActor
final class QuotaNotificationService: QuotaNotificationServicing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func sendFiveHourResetNotification(
        profileID: UUID,
        accountLabel: String,
        title: String,
        body: String,
        resetAt: Date
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = QuotaNotificationConstants.categoryIdentifier
        content.userInfo = [
            QuotaNotificationConstants.profileIDUserInfoKey: profileID.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: QuotaNotificationConstants.requestIdentifier(
                profileID: profileID,
                resetAt: resetAt
            ),
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}

final class SwitcherAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    typealias NotificationSwitchHandler = @MainActor @Sendable (UUID) async -> Void

    private let stateLock = NSLock()
    private var switchHandler: NotificationSwitchHandler?
    private struct PendingAction {
        let profileID: UUID
        let completion: NotificationCompletionHandler
    }

    private var pendingActions: [PendingAction] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: QuotaNotificationConstants.categoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: QuotaNotificationConstants.switchActionIdentifier,
                        title: L10n.string("notification_switch_action", language: .system),
                        options: [.foreground]
                    ),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    /// Binds the app model after SwiftUI has created it and drains actions
    /// received during a cold launch in arrival order.
    func bindSwitchHandler(_ handler: @escaping NotificationSwitchHandler) {
        stateLock.lock()
        switchHandler = handler
        let pending = pendingActions
        pendingActions.removeAll(keepingCapacity: false)
        stateLock.unlock()
        for action in pending {
            dispatch(action.profileID, using: handler, completion: action.completion)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == QuotaNotificationConstants.switchActionIdentifier,
              let profileID = Self.profileID(from: response.notification.request.content.userInfo)
        else {
            completionHandler()
            return
        }

        let completion = NotificationCompletionHandler(completionHandler)
        stateLock.lock()
        let switchHandler = self.switchHandler
        if switchHandler == nil {
            pendingActions.append(PendingAction(profileID: profileID, completion: completion))
        }
        stateLock.unlock()

        guard let switchHandler else {
            return
        }
        dispatch(profileID, using: switchHandler, completion: completion)
    }

    static func profileID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawValue = userInfo[QuotaNotificationConstants.profileIDUserInfoKey] as? String else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func dispatch(
        _ profileID: UUID,
        using handler: @escaping NotificationSwitchHandler,
        completion: NotificationCompletionHandler
    ) {
        Task { @MainActor in
            await handler(profileID)
            completion.call()
        }
    }
}
