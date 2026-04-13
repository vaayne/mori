import AppKit
import Combine
import SwiftUI
import MoriTerminal
import MoriUI

final class MainWindowController: NSWindowController {
    var onWindowAppearanceInvalidated: (() -> Void)?

    // MARK: - Toolbar

    private enum ToolbarID {
        static let main = NSToolbar.Identifier("MoriMainToolbar")
        static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
        static let files = NSToolbarItem.Identifier("openFiles")
        static let git = NSToolbarItem.Identifier("openGit")
        static let splitRight = NSToolbarItem.Identifier("splitRight")
        static let splitDown = NSToolbarItem.Identifier("splitDown")
    }

    /// Maps toolbar item identifiers to their shortcut hint strings.
    private static let toolbarShortcutHints: [NSToolbarItem.Identifier: String] = [
        ToolbarID.toggleSidebar: "⌘B",
        ToolbarID.files: "⌘E",
        ToolbarID.git: "⌘G",
        ToolbarID.splitRight: "⌘D",
        ToolbarID.splitDown: "⇧⌘D",
    ]

    var onToggleSidebar: (() -> Void)?
    var onToggleFiles: (() -> Void)?
    var onToggleGit: (() -> Void)?
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?
    var onShowCreateWorktreePanel: (() -> Void)?

    /// The hosting view for the update pill, overlaid on the titlebar.
    private var updateOverlay: NSView?

    // MARK: - Shortcut Hints

    private let shortcutHintMonitor = ShortcutHintModifierMonitor()
    private var shortcutHintCancellable: AnyCancellable?
    private var shortcutHintOverlays: [NSView] = []

    // MARK: - Init

    init(themeInfo: GhosttyThemeInfo = .fallback) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        configureToolbar()
        startShortcutHintMonitor()
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
        let frameString = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frameString, forKey: Self.frameKey)
    }

    /// Show the worktree creation panel. Delegates to the callback wired by AppDelegate.
    func showCreateWorktreePanel() {
        onShowCreateWorktreePanel?()
    }

    /// Adds the update pill as an overlay pinned to the top-right of the titlebar area.
    func addUpdateAccessory(viewModel: UpdateViewModel) {
        guard let window else { return }

        // Find the titlebar container (themeFrame) to overlay onto
        guard let themeFrame = window.contentView?.superview else { return }

        let hostingView = NSHostingView(rootView: UpdatePill(model: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        themeFrame.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: themeFrame.topAnchor, constant: 5),
            hostingView.trailingAnchor.constraint(equalTo: themeFrame.trailingAnchor, constant: -10),
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

    // MARK: - Toolbar

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: ToolbarID.main)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unifiedCompact
    }

    @objc private func toggleSidebarClicked() {
        onToggleSidebar?()
    }

    @objc private func toggleFilesClicked() {
        onToggleFiles?()
    }

    @objc private func toggleGitClicked() {
        onToggleGit?()
    }

    @objc private func splitRightClicked() {
        onSplitRight?()
    }

    @objc private func splitDownClicked() {
        onSplitDown?()
    }

    // MARK: - Shortcut Hint Overlays

    private func startShortcutHintMonitor() {
        shortcutHintMonitor.start()
        shortcutHintCancellable = shortcutHintMonitor.$areHintsVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                if visible {
                    self?.showToolbarShortcutHints()
                } else {
                    self?.hideToolbarShortcutHints()
                }
            }
    }

    private func showToolbarShortcutHints() {
        guard let toolbar = window?.toolbar else { return }

        for item in toolbar.items {
            guard let hint = Self.toolbarShortcutHints[item.itemIdentifier],
                  let itemView = item.value(forKey: "view") as? NSView else { continue }

            let pill = NSHostingView(rootView: ShortcutHintPill(hint))
            pill.translatesAutoresizingMaskIntoConstraints = false
            itemView.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: itemView.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: itemView.topAnchor, constant: 2),
            ])
            pill.alphaValue = 0
            shortcutHintOverlays.append(pill)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for overlay in shortcutHintOverlays {
                overlay.animator().alphaValue = 1
            }
        }
    }

    private func hideToolbarShortcutHints() {
        let overlays = shortcutHintOverlays
        shortcutHintOverlays.removeAll()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for overlay in overlays {
                overlay.animator().alphaValue = 0
            }
        }, completionHandler: {
            Task { @MainActor in
                for overlay in overlays {
                    overlay.removeFromSuperview()
                }
            }
        })
    }
}

// MARK: - NSToolbarDelegate

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

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.toggleSidebar,
            .flexibleSpace,
            ToolbarID.files,
            ToolbarID.git,
            ToolbarID.splitRight,
            ToolbarID.splitDown,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.toggleSidebar,
            ToolbarID.files,
            ToolbarID.git,
            ToolbarID.splitRight,
            ToolbarID.splitDown,
            .flexibleSpace,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let compactSplitSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)

        switch itemIdentifier {
        case ToolbarID.toggleSidebar:
            item.label = .localized("Toggle Sidebar")
            item.paletteLabel = .localized("Toggle Sidebar")
            item.toolTip = .localized("Show or hide the sidebar (⌘B)")
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: .localized("Toggle Sidebar"))
            item.target = self
            item.action = #selector(toggleSidebarClicked)
            return item
        case ToolbarID.files:
            item.label = .localized("Files")
            item.paletteLabel = .localized("Files")
            item.toolTip = .localized("Open Files Companion Pane (⌘E)")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: .localized("Files"))
            item.target = self
            item.action = #selector(toggleFilesClicked)
            return item
        case ToolbarID.git:
            item.label = .localized("Git")
            item.paletteLabel = .localized("Git")
            item.toolTip = .localized("Open Git Companion Pane (⌘G)")
            item.image = NSImage(systemSymbolName: "point.topleft.down.curvedto.point.bottomright.up", accessibilityDescription: .localized("Git"))
            item.target = self
            item.action = #selector(toggleGitClicked)
            return item
        case ToolbarID.splitRight:
            item.label = .localized("Split Right")
            item.paletteLabel = .localized("Split Right")
            item.toolTip = .localized("Split the current pane to the right (⌘D)")
            item.image = NSImage(
                systemSymbolName: "rectangle.split.2x1",
                accessibilityDescription: .localized("Split Right")
            )?.withSymbolConfiguration(compactSplitSymbolConfiguration)
            item.target = self
            item.action = #selector(splitRightClicked)
            return item
        case ToolbarID.splitDown:
            item.label = .localized("Split Down")
            item.paletteLabel = .localized("Split Down")
            item.toolTip = .localized("Split the current pane downward (⇧⌘D)")
            item.image = NSImage(
                systemSymbolName: "rectangle.split.1x2",
                accessibilityDescription: .localized("Split Down")
            )?.withSymbolConfiguration(compactSplitSymbolConfiguration)
            item.target = self
            item.action = #selector(splitDownClicked)
            return item
        default:
            return nil
        }
    }
}
