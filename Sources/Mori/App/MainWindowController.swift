import AppKit
import MoriTerminal

final class MainWindowController: NSWindowController {

    // MARK: - Toolbar

    private enum ToolbarID {
        static let main = NSToolbar.Identifier("MoriMainToolbar")
        static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
    }

    var onToggleSidebar: (() -> Void)?
    var onShowCreateWorktreePanel: (() -> Void)?

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
        window.backgroundColor = themeInfo.background
        window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window.center()

        super.init(window: window)

        configureToolbar()
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

    /// Adds the update pill as a trailing titlebar accessory.
    func addUpdateAccessory(viewModel: UpdateViewModel) {
        let accessory = UpdateAccessoryView(model: viewModel)
        window?.addTitlebarAccessoryViewController(accessory)
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
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.toggleSidebar, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.toggleSidebar, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarID.toggleSidebar else { return nil }
        let item = NSToolbarItem(itemIdentifier: ToolbarID.toggleSidebar)
        item.label = .localized("Toggle Sidebar")
        item.paletteLabel = .localized("Toggle Sidebar")
        item.toolTip = .localized("Show or hide the sidebar (⌘0)")
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: .localized("Toggle Sidebar"))
        item.target = self
        item.action = #selector(toggleSidebarClicked)
        return item
    }
}
