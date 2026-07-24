import AppKit
import MoriCore

/// Root page of the command panel: fuzzy search over projects, worktrees,
/// windows, agents, and actions. Wraps `CommandPaletteDataSource` unchanged;
/// selection routing stays with the AppDelegate via `onSelectItem`.
@MainActor
final class RootSearchPage: CommandPanelPage {

    /// Called after the panel dismisses. The caller routes to WorkspaceManager.
    var onSelectItem: ((CommandPaletteItem) -> Void)?

    /// Supplies a configured workspace-creation page for the "Create Worktree"
    /// action so it pushes in place instead of dismissing. nil (e.g. no project
    /// selected) falls back to the dismiss-then-route path, which surfaces the
    /// existing alert.
    var makeWorkspacePage: (() -> CommandPanelPage?)?

    private let dataSource: CommandPaletteDataSource
    private var resultsById: [String: CommandPaletteItem] = [:]
    private var orderedIds: [String] = []

    init(appState: AppState) {
        self.dataSource = CommandPaletteDataSource(appState: appState)
    }

    // MARK: - CommandPanelPage

    var placeholder: String { .localized("Search projects, worktrees, windows, actions...") }
    var heightPolicy: CommandPanelHeightPolicy { .fitsRows(maxVisibleRows: 10) }
    var onRowsChanged: (() -> Void)?
    var onConfirmRequested: (() -> Void)?

    func rows(for query: String) -> [CommandPanelRow] {
        let items = dataSource.search(query: query)
        resultsById = [:]
        orderedIds = []
        return items.map { item in
            let id = Self.rowId(for: item)
            resultsById[id] = item
            orderedIds.append(id)
            return CommandPanelRow.item(
                id: id,
                iconName: item.iconName,
                title: item.title,
                subtitle: item.subtitle,
                trailingText: item.shortcutHint ?? item.typeLabel,
                trailingIsShortcut: item.shortcutHint != nil
            )
        }
    }

    func defaultSelectionId(for query: String) -> String? {
        orderedIds.first
    }

    func confirm(rowId: String) -> CommandPanelConfirmResult {
        guard let item = resultsById[rowId] else { return .stay }
        if case .action(let actionId, _, _) = item, actionId == "action.create-worktree",
           let workspacePage = makeWorkspacePage?() {
            return .push(workspacePage)
        }
        return .dismiss(then: { [onSelectItem] in
            onSelectItem?(item)
        })
    }

    // MARK: - Identity

    /// Stable across rebuilds: derived from the item's own identifiers, never
    /// from its position in the result list.
    private static func rowId(for item: CommandPaletteItem) -> String {
        switch item {
        case .project(let id, _): return "project-\(id.uuidString)"
        case .worktree(let id, _, _, _): return "worktree-\(id.uuidString)"
        case .window(let id, _, _, _): return "window-\(id)"
        case .agent(let windowId, _, _, _): return "agent-\(windowId)"
        case .action(let id, _, _): return "action-\(id)"
        }
    }
}
