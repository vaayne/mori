import AppKit
import SwiftUI
import MoriTerminal
import MoriUI

final class MainWindowController: NSWindowController {
    var onWindowAppearanceInvalidated: (() -> Void)?
    var onShowCreateWorktreePanel: (() -> Void)?

    /// The hosting view for the update pill, overlaid on the window's top-right corner.
    private var updateOverlay: NSView?

    // MARK: - Init

    init(themeInfo: GhosttyThemeInfo = .fallback) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 500)
        window.title = "Mori"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = themeInfo.effectiveBackground
        window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window.center()

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    private static let frameKey = "MoriMainWindowFrame"

    func restoreSavedFrame() {
        guard let window,
              let frameString = UserDefaults.standard.string(forKey: Self.frameKey) else { return }
        let frame = NSRectFromString(frameString)
        guard !frame.isEmpty else { return }
        window.setFrame(frame, display: false)
    }

    func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
    }

    func showCreateWorktreePanel() {
        onShowCreateWorktreePanel?()
    }

    func addUpdateAccessory(viewModel: UpdateViewModel) {
        guard let window else { return }
        guard let themeFrame = window.contentView?.superview else { return }

        let hostingView = NSHostingView(rootView: UpdatePill(model: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        themeFrame.addSubview(hostingView)

        // Clear the header's trailing companion toggle (24pt button + 14pt margin) so the
        // pill never lands on top of it when an update is available.
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: themeFrame.topAnchor, constant: 5),
            hostingView.trailingAnchor.constraint(equalTo: themeFrame.trailingAnchor, constant: -48),
        ])

        self.updateOverlay = hostingView
    }

    func updateTitle(projectName: String?, worktreeName: String? = nil) {
        var parts: [String] = []
        if let worktreeName { parts.append(worktreeName) }
        if let projectName { parts.append(projectName) }
        parts.append("Mori")
        window?.title = parts.joined(separator: " — ")
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowDidEnterFullScreen(_ notification: Notification) {
        onWindowAppearanceInvalidated?()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        onWindowAppearanceInvalidated?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onWindowAppearanceInvalidated?()
    }

    func windowDidResignKey(_ notification: Notification) {
        onWindowAppearanceInvalidated?()
    }
}
