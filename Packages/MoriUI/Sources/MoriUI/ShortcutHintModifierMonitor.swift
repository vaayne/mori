import AppKit
import Combine

/// Monitors the Cmd key and publishes whether shortcut hints should be visible.
///
/// Shows hints only after an intentional 300ms hold of the Cmd key alone.
/// Dismisses immediately on key release, any keystroke, window resign, or app deactivation.
/// Suppressed while the shortcut recorder is active.
///
/// Create one instance per window/container — not per leaf view.
@MainActor
public final class ShortcutHintModifierMonitor: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var areHintsVisible = false

    // MARK: - Private

    private static let intentionalHoldDelay: Duration = .milliseconds(300)

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var revealTask: Task<Void, Never>?

    private var windowNotificationObservers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    public init() {}

    /// Begin monitoring. Call from `onAppear`.
    public func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event.modifierFlags, eventWindow: event.window)
            }
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.cancelHints()
            }
            return event
        }

        // Dismiss on window resign key
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelHints()
            }
        }

        // Dismiss on app deactivation
        let deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelHints()
            }
        }

        windowNotificationObservers = [resignObserver, deactivateObserver]
    }

    /// Stop monitoring. Call from `onDisappear`.
    public func stop() {
        cancelHints()
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        for observer in windowNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowNotificationObservers.removeAll()
    }

    // MARK: - Internal

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags, eventWindow: NSWindow?) {
        guard shouldShowHints(for: flags) else {
            cancelHints()
            return
        }

        // Already visible or pending — don't re-arm
        guard !areHintsVisible, revealTask == nil else { return }

        revealTask = Task {
            try? await Task.sleep(for: Self.intentionalHoldDelay)
            guard !Task.isCancelled else { return }
            areHintsVisible = true
        }
    }

    private func cancelHints() {
        revealTask?.cancel()
        revealTask = nil
        if areHintsVisible {
            areHintsVisible = false
        }
    }

    /// Only trigger when exactly Cmd is held (no other modifiers).
    private func shouldShowHints(for flags: NSEvent.ModifierFlags) -> Bool {
        // Suppress during shortcut recording
        if isRecordingShortcut { return false }

        let normalized = flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        return normalized == [.command]
    }
}
