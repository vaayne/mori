import AppKit

final class MainWindowController: NSWindowController {

    // MARK: - Toolbar identifiers

    private enum ToolbarID {
        static let main = NSToolbar.Identifier("MoriMainToolbar")
        static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
        static let addProject = NSToolbarItem.Identifier("addProject")
    }

    // MARK: - Callbacks

    var onAddProject: (() -> Void)?
    var onToggleSidebar: (() -> Void)?

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 500)
        window.title = "Mori"
        window.center()

        super.init(window: window)

        configureToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func updateTitle(projectName: String?) {
        window?.title = projectName.map { "\($0) — Mori" } ?? "Mori"
    }

    // MARK: - Toolbar

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: ToolbarID.main)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = true
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.toggleSidebar, .flexibleSpace, ToolbarID.addProject]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.toggleSidebar, ToolbarID.addProject, .flexibleSpace, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: ToolbarID.toggleSidebar)
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Show or hide the sidebar (Cmd+0)"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            item.target = self
            item.action = #selector(toggleSidebarClicked)
            return item
        case ToolbarID.addProject:
            let item = NSToolbarItem(itemIdentifier: ToolbarID.addProject)
            item.label = "Add Project"
            item.paletteLabel = "Add Project"
            item.toolTip = "Add a project folder"
            item.image = NSImage(systemSymbolName: "plus.rectangle.on.folder", accessibilityDescription: "Add Project")
            item.target = self
            item.action = #selector(addProjectClicked)
            return item
        default:
            return nil
        }
    }

    @objc private func toggleSidebarClicked() {
        onToggleSidebar?()
    }

    @objc private func addProjectClicked() {
        onAddProject?()
    }
}
