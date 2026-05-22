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
        static let openProject = NSToolbarItem.Identifier("openProject")
        static let commandPalette = NSToolbarItem.Identifier("commandPalette")
        static let agentDashboard = NSToolbarItem.Identifier("agentDashboard")
        static let settings = NSToolbarItem.Identifier("settings")
        static let files = NSToolbarItem.Identifier("openFiles")
        static let git = NSToolbarItem.Identifier("openGit")
        static let pullRequest = NSToolbarItem.Identifier("openPullRequest")
        static let splitRight = NSToolbarItem.Identifier("splitRight")
        static let splitDown = NSToolbarItem.Identifier("splitDown")
    }

    private struct ToolbarItemDef {
        let id: NSToolbarItem.Identifier
        let label: String
        let toolTip: String
        let symbol: String
        let hint: String
        let callback: KeyPath<MainWindowController, (() -> Void)?>
    }

    private static let toolbarItemDefs: [ToolbarItemDef] = [
        ToolbarItemDef(id: ToolbarID.toggleSidebar, label: .localized("Toggle Sidebar"),
                       toolTip: .localized("Show or hide the sidebar (⌘B)"),
                       symbol: "sidebar.left", hint: "⌘B", callback: \.onToggleSidebar),
        ToolbarItemDef(id: ToolbarID.openProject, label: .localized("Open Project"),
                       toolTip: .localized("Open Project (⇧⌘O)"),
                       symbol: "plus.rectangle.on.folder", hint: "⇧⌘O", callback: \.onOpenProject),
        ToolbarItemDef(id: ToolbarID.commandPalette, label: .localized("Command Palette"),
                       toolTip: .localized("Command Palette (⇧⌘P)"),
                       symbol: "text.magnifyingglass", hint: "⇧⌘P", callback: \.onOpenCommandPalette),
        ToolbarItemDef(id: ToolbarID.agentDashboard, label: .localized("Agent Dashboard"),
                       toolTip: .localized("Agent Dashboard (⇧⌘A)"),
                       symbol: "square.grid.2x2", hint: "⇧⌘A", callback: \.onToggleAgentDashboard),
        ToolbarItemDef(id: ToolbarID.settings, label: .localized("Settings"),
                       toolTip: .localized("Settings (⌘,)"),
                       symbol: "gearshape", hint: "⌘,", callback: \.onOpenSettings),
        ToolbarItemDef(id: ToolbarID.files, label: .localized("Files"),
                       toolTip: .localized("Open Files Companion Pane (⌘E)"),
                       symbol: "folder", hint: "⌘E", callback: \.onToggleFiles),
        ToolbarItemDef(id: ToolbarID.git, label: .localized("Git"),
                       toolTip: .localized("Open Git Companion Pane (⌘G)"),
                       symbol: "point.topleft.down.curvedto.point.bottomright.up", hint: "⌘G", callback: \.onToggleGit),
        ToolbarItemDef(id: ToolbarID.pullRequest, label: .localized("PR"),
                       toolTip: .localized("Open Pull Request Companion Pane"),
                       symbol: "arrow.triangle.pull", hint: "", callback: \.onTogglePullRequest),
        ToolbarItemDef(id: ToolbarID.splitRight, label: .localized("Split Right"),
                       toolTip: .localized("Split the current pane to the right (⌘D)"),
                       symbol: "rectangle.split.2x1", hint: "⌘D", callback: \.onSplitRight),
        ToolbarItemDef(id: ToolbarID.splitDown, label: .localized("Split Down"),
                       toolTip: .localized("Split the current pane downward (⇧⌘D)"),
                       symbol: "rectangle.split.1x2", hint: "⇧⌘D", callback: \.onSplitDown),
    ]

    var onToggleSidebar: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenCommandPalette: (() -> Void)?
    var onToggleAgentDashboard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleFiles: (() -> Void)?
    var onToggleGit: (() -> Void)?
    var onTogglePullRequest: (() -> Void)?
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?
    var onShowCreateWorktreePanel: (() -> Void)?

    /// The hosting view for the update pill, overlaid on the titlebar.
    private var updateOverlay: NSView?

    // MARK: - Shortcut Hints

    private let shortcutHintMonitor = ShortcutHintModifierMonitor()
    private var shortcutHintCancellable: AnyCancellable?
    private var shortcutHintOverlays: [NSView] = []
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

    private func makeToolbarItem(for def: ToolbarItemDef) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: def.id)
        item.label = def.label
        item.paletteLabel = def.label
        item.toolTip = def.toolTip

        let image = NSImage(systemSymbolName: def.symbol, accessibilityDescription: def.label)?
            .withSymbolConfiguration(Self.symbolConfig) ?? NSImage()

        let button = NSButton(image: image, target: self, action: #selector(toolbarAction(_:)))
        button.bezelStyle = NSButton.BezelStyle.toolbar
        button.imagePosition = NSControl.ImagePosition.imageOnly
        button.setAccessibilityLabel(def.label)
        button.identifier = NSUserInterfaceItemIdentifier(def.id.rawValue)

        item.view = button
        toolbarButtonViews[def.id] = button
        return item
    }

    @objc private func toolbarAction(_ sender: NSButton) {
        guard let senderId = sender.identifier?.rawValue,
              let def = Self.toolbarItemDefs.first(where: { $0.id.rawValue == senderId }) else { return }
        self[keyPath: def.callback]?()
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

        for def in Self.toolbarItemDefs {
            guard !def.hint.isEmpty,
                  let anchor = toolbarButtonViews[def.id], anchor.window != nil else { continue }

            let anchorRect = anchor.convert(anchor.bounds, to: themeFrame)
            let pill = NSHostingView(rootView: ShortcutHintPill(def.hint))
            let pillSize = pill.fittingSize

            pill.frame = NSRect(
                x: anchorRect.midX - pillSize.width / 2,
                y: anchorRect.maxY + 2,
                width: pillSize.width,
                height: pillSize.height
            )
            pill.alphaValue = 0
            themeFrame.addSubview(pill)
            shortcutHintOverlays.append(pill)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for overlay in self.shortcutHintOverlays {
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

    private static let defaultItemIds: [NSToolbarItem.Identifier] = [
        ToolbarID.toggleSidebar,
        ToolbarID.openProject,
        ToolbarID.commandPalette,
        ToolbarID.agentDashboard,
        .flexibleSpace,
        ToolbarID.files,
        ToolbarID.git,
        ToolbarID.pullRequest,
        ToolbarID.splitRight,
        ToolbarID.splitDown,
        ToolbarID.settings,
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultItemIds
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultItemIds
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let def = Self.toolbarItemDefs.first(where: { $0.id == itemIdentifier }) else {
            return nil
        }
        return makeToolbarItem(for: def)
    }
}
