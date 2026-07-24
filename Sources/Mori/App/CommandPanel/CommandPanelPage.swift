import AppKit

/// What the panel does after a row is confirmed. Returned by the page so
/// navigation stays a page decision while the container executes it.
@MainActor
enum CommandPanelConfirmResult {
    /// Hide the panel first, then run the side effect — the panel must be gone
    /// before navigation repaints the main window underneath it.
    case dismiss(then: (() -> Void)?)
    /// Switch to another page inside the same panel.
    case push(CommandPanelPage)
    /// Keep the panel open and unchanged (confirm landed on nothing actionable).
    case stay
}

/// One display row. Pages map their domain models into this; the container
/// never sees domain types. `id` must be stable across async rebuilds — it is
/// how the container preserves the highlighted row when sections shift.
struct CommandPanelRow {
    enum Kind {
        case sectionHeader
        case hint
        case item
    }

    let id: String
    let kind: Kind
    let iconName: String?
    let title: String
    let subtitle: String?
    let trailingText: String?
    /// Shortcut hints render monospaced; type labels render in the system font.
    let trailingIsShortcut: Bool

    var isSelectable: Bool { kind == .item }

    static func sectionHeader(id: String, title: String) -> CommandPanelRow {
        CommandPanelRow(
            id: id, kind: .sectionHeader, iconName: nil, title: title,
            subtitle: nil, trailingText: nil, trailingIsShortcut: false
        )
    }

    static func hint(id: String, iconName: String = "info.circle", title: String) -> CommandPanelRow {
        CommandPanelRow(
            id: id, kind: .hint, iconName: iconName, title: title,
            subtitle: nil, trailingText: nil, trailingIsShortcut: false
        )
    }

    static func item(
        id: String,
        iconName: String? = nil,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        trailingIsShortcut: Bool = false
    ) -> CommandPanelRow {
        CommandPanelRow(
            id: id, kind: .item, iconName: iconName, title: title,
            subtitle: subtitle, trailingText: trailingText, trailingIsShortcut: trailingIsShortcut
        )
    }
}

/// How the panel sizes itself while a page is frontmost.
enum CommandPanelHeightPolicy {
    /// Grow and shrink with the row count, capped at `maxVisibleRows`.
    case fitsRows(maxVisibleRows: Int)
    /// Fixed content height; the list scrolls.
    case fixed(CGFloat)
}

/// A page of the command panel: a placeholder, a row list keyed by the query,
/// and a confirm action. The container owns all chrome, key routing, and the
/// page stack; pages own data and semantics only.
@MainActor
protocol CommandPanelPage: AnyObject {
    var placeholder: String { get }
    /// Shown as "‹ title" before the search field on pushed pages; nil on the root.
    var breadcrumbTitle: String? { get }
    var heightPolicy: CommandPanelHeightPolicy { get }

    /// Set by the container when the page becomes current. Call it when async
    /// data changes the row set for the unchanged query (e.g. a fetch landing).
    /// The container ignores notifications from non-current pages.
    var onRowsChanged: (() -> Void)? { get set }

    /// Current page came on screen: reset transient state, start fetches.
    func activate()
    /// Page left the screen (popped, dismissed, or hidden): invalidate
    /// in-flight work so late completions can't touch another page.
    func deactivate()

    func rows(for query: String) -> [CommandPanelRow]

    /// The row Enter should act on right after `query` changed. Return nil to
    /// leave nothing selected. After an async rebuild (same query) the container
    /// first tries to re-find the previously selected id and only falls back here.
    func defaultSelectionId(for query: String) -> String?

    /// Highlight moved (keyboard, mouse, or rebuild). Pages use this to drive
    /// accessory state; the container calls it with nil when nothing is selected.
    func selectionDidChange(rowId: String?)

    func confirm(rowId: String) -> CommandPanelConfirmResult

    /// Tab pressed while the search field is focused. Return true if the page
    /// consumed it (e.g. moved focus to an accessory control).
    func handleTab() -> Bool
}

extension CommandPanelPage {
    var breadcrumbTitle: String? { nil }
    func activate() {}
    func deactivate() {}
    func selectionDidChange(rowId: String?) {}
    func handleTab() -> Bool { false }
}
