import Foundation
import MoriCore
import UserNotifications

/// Manages macOS user notifications for Mori events.
/// Posts notifications via UNUserNotificationCenter when badge transitions
/// indicate attention-worthy events (agent waiting, errors, long-running complete).
@MainActor
final class NotificationManager: NSObject {

    /// Notification category identifier for Mori notifications.
    static let categoryIdentifier = "mori.notification"

    /// Callback invoked when user clicks a notification.
    /// Parameters: (windowId, worktreeId)
    var onNotificationClick: ((String, String) -> Void)?

    private var permissionRequested = false
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    override init() {
        super.init()
        if hasBundle { setupCategory() }
    }

    /// Request notification permission on first use.
    func requestPermissionIfNeeded() {
        guard hasBundle, !permissionRequested else { return }
        permissionRequested = true

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Post a notification for a badge transition event.
    /// - Parameters:
    ///   - event: The notification event type.
    ///   - windowTitle: Title of the window that triggered the event.
    ///   - worktreeName: Name of the parent worktree.
    ///   - windowId: tmux window ID (encoded in userInfo for click handling).
    ///   - worktreeId: Worktree UUID string (encoded in userInfo for click handling).
    func notify(
        _ event: NotificationEvent,
        windowTitle: String,
        worktreeName: String,
        windowId: String,
        worktreeId: String
    ) {
        requestPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "windowId": windowId,
            "worktreeId": worktreeId,
        ]

        switch event {
        case .agentWaiting:
            content.title = "Agent Waiting for Input"
            content.body = "\(windowTitle) in \(worktreeName) needs your attention."
            content.sound = .default
        case .commandError:
            content.title = "Command Error"
            content.body = "\(windowTitle) in \(worktreeName) encountered an error."
            content.sound = .default
        case .longRunningComplete:
            content.title = "Command Finished"
            content.body = "\(windowTitle) in \(worktreeName) has completed."
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "mori.\(windowId).\(event.rawValue).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        guard hasBundle else { return }
        UNUserNotificationCenter.current().add(request)
    }

    /// Set up notification category for click handling.
    private func setupCategory() {
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
