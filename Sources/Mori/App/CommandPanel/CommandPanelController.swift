import AppKit
import MoriTerminal

/// The panel window. A subclass (rather than an event monitor) so Esc and ⌘⏎
/// keep working when focus sits on an accessory control instead of the search
/// field — the responder chain ends here for any first responder in the panel.
@MainActor
private final class CommandPanelWindow: NSPanel {
    var onEscape: (() -> Void)?
    var onCommandReturn: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Floating command panel: one window, one chrome, a stack of pages.
///
/// The container owns everything visual and interactive — material, search row,
/// list, key routing, sizing, theming — while `CommandPanelPage`s supply rows
/// and semantics. Pushing a page swaps content in place; the panel never
/// hands off to a second window.
@MainActor
final class CommandPanelController: NSWindowController, ThemedSurface {

    var themedWindow: NSWindow? { nil }

    // MARK: - State

    private var pageStack: [CommandPanelPage] = []
    private var currentPage: CommandPanelPage? { pageStack.last }
    private var rows: [CommandPanelRow] = []
    private var selectedIndex: Int = -1
    private var themeInfo: GhosttyThemeInfo = .fallback

    // MARK: - Views

    private let searchField = PanelSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let blurView = PanelBlurView()
    private let tintView = PanelTintView()
    private let searchIconView = NSImageView()
    private let separatorView = PanelSeparatorView()
    private let breadcrumbButton = NSButton()
    private let footerContainer = NSView()
    private let footerSeparator = PanelSeparatorView()
    private var footerHeightConstraint: NSLayoutConstraint?
    private var iconLeadingDefault: NSLayoutConstraint?
    private var iconLeadingAfterBreadcrumb: NSLayoutConstraint?

    // MARK: - Layout Constants

    enum Layout {
        static let panelWidth: CGFloat = 520
        static let cornerRadius: CGFloat = 12
        static let searchAreaHeight: CGFloat = 48
        static let searchIconSize: CGFloat = 15
        static let searchIconLeading: CGFloat = 20
        static let searchTextSpacing: CGFloat = 9
        static let separatorHeight: CGFloat = 0.5
        static let listTopPadding: CGFloat = 4
        static let listHorizontalInset: CGFloat = 8
        static let listBottomInset: CGFloat = 8
        static let itemRowHeight: CGFloat = 32
        static let sectionHeaderRowHeight: CGFloat = 24
        static let cellIconSize: CGFloat = 16
        static let cellLeadingPadding: CGFloat = 12
        static let cellSpacing: CGFloat = 10
        static let cellTrailingPadding: CGFloat = 10
        static let titleFontSize: CGFloat = 13
        static let subtitleFontSize: CGFloat = 11
        static let trailingFontSize: CGFloat = 11
        static let searchFontSize: CGFloat = 16
        static let panelTopOffset: CGFloat = 80
        static let footerHeight: CGFloat = 44
    }

    // MARK: - Init

    init(rootPage: CommandPanelPage) {
        let panel = CommandPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        // Pages carry text input, so the panel always takes key focus.
        panel.becomesKeyOnlyIfNeeded = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.rootPage = rootPage

        super.init(window: panel)

        panel.onEscape = { [weak self] in self?.handleEscape() }
        panel.onCommandReturn = { [weak self] in self?.confirmSelection() }
        setupUI()
    }

    private let rootPage: CommandPanelPage

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Same-key open/close: hidden → open on the root page; visible → dismiss,
    /// regardless of which page is frontmost (see the entry transition table).
    func toggle() {
        if window?.isVisible == true {
            dismiss()
        } else {
            open(with: rootPage)
        }
    }

    /// Open the panel fresh with `page` as the entire stack. Any previous
    /// state — stack, query, in-flight fetches — is discarded.
    func open(with page: CommandPanelPage) {
        guard let panel = window else { return }
        tearDownStack()
        pageStack = [page]
        bindCurrentPage()
        page.activate()
        resetQueryAndReload()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func dismiss() {
        tearDownStack()
        window?.orderOut(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Whether `page` is currently the frontmost page of a visible panel.
    func isShowing(_ page: CommandPanelPage) -> Bool {
        isVisible && currentPage === page
    }

    func push(_ page: CommandPanelPage) {
        guard window?.isVisible == true else {
            open(with: page)
            return
        }
        currentPage?.deactivate()
        currentPage?.onRowsChanged = nil
        currentPage?.onConfirmRequested = nil
        pageStack.append(page)
        bindCurrentPage()
        page.activate()
        resetQueryAndReload()
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Page stack

    private func bindCurrentPage() {
        guard let page = currentPage else { return }
        page.onRowsChanged = { [weak self, weak page] in
            guard let self, let page, self.currentPage === page else { return }
            self.reloadRows(preserveSelection: true)
        }
        page.onConfirmRequested = { [weak self, weak page] in
            guard let self, let page, self.currentPage === page else { return }
            self.confirmSelection()
        }
        searchField.placeholderString = page.placeholder
        updateBreadcrumb(for: page)
        installFooter(for: page)
        applyTheme(themeInfo)
    }

    private func updateBreadcrumb(for page: CommandPanelPage) {
        if let title = page.breadcrumbTitle {
            breadcrumbButton.isHidden = false
            breadcrumbButton.attributedTitle = NSAttributedString(
                string: "‹ \(title)",
                attributes: [
                    .foregroundColor: themeInfo.foreground.withAlphaComponent(0.7),
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ]
            )
            iconLeadingDefault?.isActive = false
            iconLeadingAfterBreadcrumb?.isActive = true
        } else {
            breadcrumbButton.isHidden = true
            iconLeadingAfterBreadcrumb?.isActive = false
            iconLeadingDefault?.isActive = true
        }
    }

    private func installFooter(for page: CommandPanelPage) {
        for subview in footerContainer.subviews where subview !== footerSeparator {
            subview.removeFromSuperview()
        }
        if let footer = page.footerView {
            footer.translatesAutoresizingMaskIntoConstraints = false
            footerContainer.addSubview(footer)
            NSLayoutConstraint.activate([
                footer.topAnchor.constraint(equalTo: footerSeparator.bottomAnchor),
                footer.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
                footer.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
                footer.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
            ])
            footerContainer.isHidden = false
            footerHeightConstraint?.constant = Layout.footerHeight
        } else {
            footerContainer.isHidden = true
            footerHeightConstraint?.constant = 0
        }
    }

    private func tearDownStack() {
        for page in pageStack {
            page.onRowsChanged = nil
            page.onConfirmRequested = nil
            page.deactivate()
        }
        pageStack = []
    }

    private func handleEscape() {
        if pageStack.count > 1 {
            pop()
        } else {
            dismiss()
        }
    }

    private func pop() {
        guard pageStack.count > 1, let leaving = pageStack.popLast() else { return }
        leaving.onRowsChanged = nil
        leaving.onConfirmRequested = nil
        leaving.deactivate()
        bindCurrentPage()
        currentPage?.activate()
        resetQueryAndReload()
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Rows & selection

    private func resetQueryAndReload() {
        searchField.stringValue = ""
        reloadRows(preserveSelection: false)
    }

    /// Rebuild rows from the current page. `preserveSelection` distinguishes an
    /// async data refresh (keep the highlighted id if it survived) from a query
    /// change (ask the page for a fresh default).
    private func reloadRows(preserveSelection: Bool) {
        guard let page = currentPage else { return }
        let query = currentQuery()
        let previousId = selectedRowId()
        rows = page.rows(for: query)

        var newIndex = -1
        if preserveSelection, let previousId,
           let idx = rows.firstIndex(where: { $0.id == previousId && $0.isSelectable }) {
            newIndex = idx
        } else if let defaultId = page.defaultSelectionId(for: query),
                  let idx = rows.firstIndex(where: { $0.id == defaultId && $0.isSelectable }) {
            newIndex = idx
        }

        tableView.reloadData()
        setSelectedIndex(newIndex, notify: true)
        resizePanel()
    }

    private func selectedRowId() -> String? {
        guard selectedIndex >= 0, selectedIndex < rows.count else { return nil }
        return rows[selectedIndex].id
    }

    private func setSelectedIndex(_ index: Int, notify: Bool) {
        let oldIndex = selectedIndex
        selectedIndex = index
        if index >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
        // Reload both endpoints so cell emphasis (pill + text alpha) tracks selection.
        var affected = IndexSet()
        if oldIndex >= 0, oldIndex < rows.count { affected.insert(oldIndex) }
        if index >= 0 { affected.insert(index) }
        if !affected.isEmpty {
            tableView.reloadData(forRowIndexes: affected, columnIndexes: IndexSet(integer: 0))
        }
        if notify {
            currentPage?.selectionDidChange(rowId: selectedRowId())
        }
    }

    private func moveSelection(by delta: Int) {
        let selectable = rows.indices.filter { rows[$0].isSelectable }
        guard !selectable.isEmpty else { return }
        if let current = selectable.firstIndex(of: selectedIndex) {
            let next = max(0, min(selectable.count - 1, current + delta))
            setSelectedIndex(selectable[next], notify: true)
        } else {
            setSelectedIndex(delta >= 0 ? selectable[0] : selectable[selectable.count - 1], notify: true)
        }
    }

    private func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < rows.count,
              rows[selectedIndex].isSelectable,
              let page = currentPage else { return }
        switch page.confirm(rowId: rows[selectedIndex].id) {
        case .dismiss(let then):
            dismiss()
            then?()
        case .push(let nextPage):
            push(nextPage)
        case .stay:
            break
        }
    }

    private func currentQuery(from notification: Notification? = nil) -> String {
        // While editing, AppKit keeps live text in the shared field editor;
        // reading it directly avoids stale stringValue reads.
        if let fieldEditor = notification?.userInfo?["NSFieldEditor"] as? NSTextView {
            return fieldEditor.string
        }
        if let fieldEditor = searchField.currentEditor() {
            return fieldEditor.string
        }
        return searchField.stringValue
    }

    // MARK: - Theme

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        self.themeInfo = themeInfo
        let appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window?.appearance = appearance
        window?.backgroundColor = .clear
        tintView.themeInfo = themeInfo
        separatorView.themeInfo = themeInfo
        searchIconView.contentTintColor = themeInfo.foreground.withAlphaComponent(0.35)
        searchField.textColor = themeInfo.foreground
        searchField.backgroundColor = .clear
        searchField.placeholderAttributedString = NSAttributedString(
            string: currentPage?.placeholder ?? "",
            attributes: [
                .foregroundColor: themeInfo.foreground.withAlphaComponent(0.45),
                .font: NSFont.systemFont(ofSize: Layout.searchFontSize),
            ]
        )
        tableView.appearance = appearance
        tableView.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        footerSeparator.themeInfo = themeInfo
        footerContainer.appearance = appearance
        if let page = currentPage {
            updateBreadcrumb(for: page)
        }
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupUI() {
        guard let panel = window else { return }

        containerView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = containerView

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.blendingMode = .behindWindow
        blurView.material = .popover
        blurView.state = .active
        containerView.addSubview(blurView)

        tintView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tintView)

        breadcrumbButton.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbButton.isBordered = false
        breadcrumbButton.setButtonType(.momentaryChange)
        breadcrumbButton.target = self
        breadcrumbButton.action = #selector(breadcrumbClicked)
        breadcrumbButton.isHidden = true
        breadcrumbButton.setContentHuggingPriority(.required, for: .horizontal)
        breadcrumbButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        containerView.addSubview(breadcrumbButton)

        searchIconView.translatesAutoresizingMaskIntoConstraints = false
        searchIconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIconView.imageScaling = .scaleProportionallyDown
        containerView.addSubview(searchIconView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: Layout.searchFontSize)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.delegate = self
        containerView.addSubview(searchField)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separatorView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rows"))
        column.width = Layout.panelWidth - Layout.listHorizontalInset * 2
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.itemRowHeight
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        containerView.addSubview(scrollView)

        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.isHidden = true
        containerView.addSubview(footerContainer)

        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.addSubview(footerSeparator)

        let footerHeight = footerContainer.heightAnchor.constraint(equalToConstant: 0)
        footerHeightConstraint = footerHeight

        let iconDefault = searchIconView.leadingAnchor.constraint(
            equalTo: containerView.leadingAnchor, constant: Layout.searchIconLeading
        )
        let iconAfterBreadcrumb = searchIconView.leadingAnchor.constraint(
            equalTo: breadcrumbButton.trailingAnchor, constant: 10
        )
        iconLeadingDefault = iconDefault
        iconLeadingAfterBreadcrumb = iconAfterBreadcrumb
        iconDefault.isActive = true

        NSLayoutConstraint.activate([
            breadcrumbButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            breadcrumbButton.centerYAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.searchAreaHeight / 2),

            footerHeight,
            footerContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            footerSeparator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: Layout.separatorHeight),
        ])

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            tintView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            searchIconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.searchIconLeading),
            searchIconView.centerYAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.searchAreaHeight / 2),
            searchIconView.widthAnchor.constraint(equalToConstant: Layout.searchIconSize),
            searchIconView.heightAnchor.constraint(equalToConstant: Layout.searchIconSize),

            searchField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: Layout.searchTextSpacing),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.searchIconLeading),
            searchField.centerYAnchor.constraint(equalTo: searchIconView.centerYAnchor),

            separatorView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.searchAreaHeight),
            separatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: Layout.separatorHeight),

            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: Layout.listTopPadding),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.listHorizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.listHorizontalInset),
            scrollView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor, constant: -Layout.listBottomInset),
        ])
    }

    // MARK: - Sizing & positioning

    private func contentHeight() -> CGFloat {
        let listHeight: CGFloat
        switch currentPage?.heightPolicy ?? .fitsRows(maxVisibleRows: 10) {
        case .fitsRows(let maxVisibleRows):
            let visible = min(max(visibleRowUnits(), 1), CGFloat(maxVisibleRows))
            listHeight = visible * Layout.itemRowHeight
        case .fixed(let height):
            listHeight = height
        }
        let footerHeight: CGFloat = currentPage?.footerView == nil ? 0 : Layout.footerHeight
        return Layout.searchAreaHeight + Layout.separatorHeight + Layout.listTopPadding
            + listHeight + Layout.listBottomInset + footerHeight
    }

    /// Row count weighted by height so section headers don't inflate the panel.
    private func visibleRowUnits() -> CGFloat {
        rows.reduce(0) { total, row in
            total + (row.kind == .sectionHeader
                ? Layout.sectionHeaderRowHeight / Layout.itemRowHeight
                : 1)
        }
    }

    private func positionPanel() {
        guard let panel = window else { return }
        let height = contentHeight()
        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.midX - Layout.panelWidth / 2
            let y = mainFrame.maxY - height - Layout.panelTopOffset
            panel.setFrame(NSRect(x: x, y: y, width: Layout.panelWidth, height: height), display: true)
        } else {
            panel.setFrame(NSRect(x: 0, y: 0, width: Layout.panelWidth, height: height), display: true)
            panel.center()
        }
    }

    /// Grow downward: the top edge stays anchored while the height changes.
    private func resizePanel() {
        guard let panel = window else { return }
        let height = contentHeight()
        var frame = panel.frame
        frame.origin.y -= height - frame.height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Actions

    @objc private func breadcrumbClicked() {
        handleEscape()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, rows[row].isSelectable else { return }
        setSelectedIndex(row, notify: true)
        confirmSelection()
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPanelController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        let typed = currentQuery(from: notification)
        // Pages may rewrite the query (pasted GitHub URL → "#123"); pushing the
        // rewrite back into the field keeps what the user sees and what filters
        // the list identical.
        if let rewritten = currentPage?.normalizeQuery(typed), rewritten != typed {
            searchField.stringValue = rewritten
            if let editor = searchField.currentEditor() {
                editor.string = rewritten
                editor.selectedRange = NSRange(location: rewritten.count, length: 0)
            }
        }
        reloadRows(preserveSelection: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // IME composition owns Enter/arrows until the candidate is committed.
        if textView.hasMarkedText() {
            return false
        }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            confirmSelection()
            return true
        case #selector(NSResponder.insertTab(_:)):
            return currentPage?.handleTab() ?? false
        default:
            return false
        }
    }
}

// MARK: - Table

extension CommandPanelController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else { return Layout.itemRowHeight }
        return rows[row].kind == .sectionHeader ? Layout.sectionHeaderRowHeight : Layout.itemRowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row >= 0 && row < rows.count && rows[row].isSelectable
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row != selectedIndex, row < rows.count, rows[row].isSelectable else { return }
        setSelectedIndex(row, notify: true)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else { return nil }
        let model = rows[row]

        if model.kind == .sectionHeader {
            return makeSectionHeaderCell(model)
        }

        let cellID = NSUserInterfaceItemIdentifier("CommandPanelItemCell")
        let cell: PanelItemCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? PanelItemCellView {
            cell = existing
        } else {
            cell = PanelItemCellView()
            cell.identifier = cellID
        }
        cell.configure(
            with: model,
            themeInfo: themeInfo,
            isSelected: row == selectedIndex
        )
        return cell
    }

    private func makeSectionHeaderCell(_ model: CommandPanelRow) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("CommandPanelHeaderCell")
        let cell: PanelSectionHeaderCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? PanelSectionHeaderCellView {
            cell = existing
        } else {
            cell = PanelSectionHeaderCellView()
            cell.identifier = cellID
        }
        cell.configure(title: model.title, themeInfo: themeInfo)
        return cell
    }
}

// MARK: - Chrome views

private final class PanelSearchField: NSTextField {}

private final class PanelBlurView: NSVisualEffectView {
    override func layout() {
        super.layout()
        // The mask clips the blur to the rounded shape — without it the
        // visual effect bleeds past the corners of the transparent window.
        maskImage = NSImage.commandPanelRoundedMask(
            size: bounds.size, radius: CommandPanelController.Layout.cornerRadius
        )
    }
}

private final class PanelTintView: NSView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = CommandPanelController.Layout.cornerRadius
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        // Near-opaque over the blur: enough bleed-through for depth, no muddy
        // gray mix in light themes.
        themeInfo.background.withAlphaComponent(themeInfo.isDark ? 0.7 : 0.85).setFill()
        path.fill()
        themeInfo.foreground.withAlphaComponent(themeInfo.isDark ? 0.14 : 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class PanelSeparatorView: NSView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        themeInfo.foreground.withAlphaComponent(themeInfo.isDark ? 0.12 : 0.08).setFill()
        dirtyRect.fill()
    }
}

// MARK: - Cells

private final class PanelItemCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let trailingField = NSTextField(labelWithString: "")
    private var isSelectedRow = false
    private var themeInfo: GhosttyThemeInfo = .fallback

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        typealias Layout = CommandPanelController.Layout

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        imageView = iconView

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: Layout.titleFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)
        textField = titleField

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = .systemFont(ofSize: Layout.subtitleFontSize)
        subtitleField.lineBreakMode = .byTruncatingTail
        addSubview(subtitleField)

        trailingField.translatesAutoresizingMaskIntoConstraints = false
        trailingField.alignment = .right
        // Truncate with an ellipsis instead of clipping mid-glyph, and never
        // compress before the title does — this is the "Projec" fix.
        trailingField.lineBreakMode = .byTruncatingTail
        addSubview(trailingField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.cellLeadingPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Layout.cellSpacing),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: Layout.cellSpacing),
            subtitleField.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingField.leadingAnchor.constraint(greaterThanOrEqualTo: subtitleField.trailingAnchor, constant: Layout.cellSpacing),
            trailingField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.cellTrailingPadding),
            trailingField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleField.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        trailingField.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingField.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(with row: CommandPanelRow, themeInfo: GhosttyThemeInfo, isSelected: Bool) {
        typealias Layout = CommandPanelController.Layout
        self.themeInfo = themeInfo
        self.isSelectedRow = isSelected

        let fg = themeInfo.foreground
        let isHint = row.kind == .hint

        if let iconName = row.iconName {
            iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            iconView.contentTintColor = fg.withAlphaComponent(isSelected ? 0.9 : 0.65)
        } else {
            iconView.image = nil
        }

        titleField.stringValue = row.title
        titleField.textColor = isHint ? fg.withAlphaComponent(0.6) : fg

        subtitleField.stringValue = row.subtitle ?? ""
        subtitleField.isHidden = row.subtitle == nil
        subtitleField.textColor = fg.withAlphaComponent(isSelected ? 0.75 : 0.58)

        if let trailing = row.trailingText {
            trailingField.stringValue = trailing
            trailingField.isHidden = false
            trailingField.font = row.trailingIsShortcut
                ? .monospacedSystemFont(ofSize: Layout.trailingFontSize, weight: .regular)
                : .systemFont(ofSize: Layout.trailingFontSize)
            trailingField.textColor = fg.withAlphaComponent(isSelected ? 0.7 : 0.45)
        } else {
            trailingField.stringValue = ""
            trailingField.isHidden = true
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            let selectionRect = bounds.insetBy(dx: 0, dy: 2)
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
            accent.withAlphaComponent(themeInfo.isDark ? 0.5 : 0.35).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

private final class PanelSectionHeaderCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CommandPanelController.Layout.cellLeadingPadding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -CommandPanelController.Layout.cellTrailingPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func configure(title: String, themeInfo: GhosttyThemeInfo) {
        label.stringValue = title.uppercased()
        label.textColor = themeInfo.foreground.withAlphaComponent(0.45)
    }
}

private extension NSImage {
    static func commandPanelRoundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius).fill()
        image.unlockFocus()
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
