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

    /// Retained references to toolbar button views keyed by item identifier.
    private var toolbarButtonViews: [NSToolbarItem.Identifier: NSView] = [:]

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

    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

    private func makeToolbarItem(
        id: NSToolbarItem.Identifier,
        label: String,
        toolTip: String,
        systemImageName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip

        let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: label)?
            .withSymbolConfiguration(Self.symbolConfig) ?? NSImage()

        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(label)

        item.view = button
        toolbarButtonViews[id] = button
        return item
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
        hideToolbarShortcutHints()
        guard let themeFrame = window?.contentView?.superview else { return }
        themeFrame.layoutSubtreeIfNeeded()

        for (id, hint) in Self.toolbarShortcutHints {
            guard let anchor = toolbarButtonViews[id], anchor.window != nil else { continue }

            let anchorRect = anchor.convert(anchor.bounds, to: themeFrame)

            let pill = NSHostingView(rootView: ShortcutHintPill(hint))
            pill.translatesAutoresizingMaskIntoConstraints = false
            themeFrame.addSubview(pill)

            // Center horizontally on the button, position above it.
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: themeFrame.leadingAnchor, constant: anchorRect.midX),
                pill.topAnchor.constraint(equalTo: themeFrame.topAnchor, constant: anchorRect.maxY + 2),
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
        guard !overlays.isEmpty else { return }

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

// MARK: - NSToolbarDelegate

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
        switch itemIdentifier {
        case ToolbarID.toggleSidebar:
            return makeToolbarItem(
                id: ToolbarID.toggleSidebar,
                label: .localized("Toggle Sidebar"),
                toolTip: .localized("Show or hide the sidebar (⌘B)"),
                systemImageName: "sidebar.left",
                action: #selector(toggleSidebarClicked)
            )
        case ToolbarID.files:
            return makeToolbarItem(
                id: ToolbarID.files,
                label: .localized("Files"),
                toolTip: .localized("Open Files Companion Pane (⌘E)"),
                systemImageName: "folder",
                action: #selector(toggleFilesClicked)
            )
        case ToolbarID.git:
            return makeToolbarItem(
                id: ToolbarID.git,
                label: .localized("Git"),
                toolTip: .localized("Open Git Companion Pane (⌘G)"),
                systemImageName: "point.topleft.down.curvedto.point.bottomright.up",
                action: #selector(toggleGitClicked)
            )
        case ToolbarID.splitRight:
            return makeToolbarItem(
                id: ToolbarID.splitRight,
                label: .localized("Split Right"),
                toolTip: .localized("Split the current pane to the right (⌘D)"),
                systemImageName: "rectangle.split.2x1",
                action: #selector(splitRightClicked)
            )
        case ToolbarID.splitDown:
            return makeToolbarItem(
                id: ToolbarID.splitDown,
                label: .localized("Split Down"),
                toolTip: .localized("Split the current pane downward (⇧⌘D)"),
                systemImageName: "rectangle.split.1x2",
                action: #selector(splitDownClicked)
            )
        default:
            return nil
        }
    }
}
