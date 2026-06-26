import AppKit
import MoriCore
import MoriTerminal

/// NSWindowController managing a floating command palette panel.
/// Contains an NSTextField for search and an NSTableView for results.
@MainActor
final class CommandPaletteController: NSWindowController {

    // MARK: - Callbacks

    /// Called when the user selects an item. The caller routes to WorkspaceManager.
    var onSelectItem: ((CommandPaletteItem) -> Void)?

    // MARK: - State

    private let dataSource: CommandPaletteDataSource
    private var results: [CommandPaletteItem] = []
    private var selectedIndex: Int = 0
    private var mode: Mode = .allItems

    // MARK: - Views

    private let searchField = PaletteSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = PaletteContainerView()
    private var themeInfo: GhosttyThemeInfo = .fallback

    // MARK: - Presentation Mode

    enum Mode: Equatable {
        case allItems

        var placeholder: String {
            .localized("Search projects, worktrees, windows, actions...")
        }
    }

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 520
        static let searchFieldHeight: CGFloat = 38
        static let rowHeight: CGFloat = 36
        static let maxVisibleRows: Int = 10
        static let panelPadding: CGFloat = 14
        static let fieldHorizontalPadding: CGFloat = 18
        static let cellIconSize: CGFloat = 17
        static let cellLeadingPadding: CGFloat = 14
        static let cellSpacing: CGFloat = 8
        static let cellTrailingPadding: CGFloat = 8
        static let titleFontSize: CGFloat = 13
        static let subtitleFontSize: CGFloat = 11
        static let shortcutFontSize: CGFloat = 11
        static let searchFontSize: CGFloat = 14.5
        static let panelTopOffset: CGFloat = 80
    }

    // MARK: - Init

    init(appState: AppState) {
        let panel = NSPanel(
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.dataSource = CommandPaletteDataSource(appState: appState)

        super.init(window: panel)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Toggle palette visibility for the requested mode.
    /// Re-pressing the same shortcut dismisses the panel; switching shortcuts swaps modes in place.
    func toggle(mode requestedMode: Mode = .allItems) {
        guard let panel = window else { return }

        if panel.isVisible, mode == requestedMode {
            dismiss()
            return
        }

        show(mode: requestedMode)
    }

    func show(mode requestedMode: Mode = .allItems) {
        mode = requestedMode
        searchField.placeholderString = requestedMode.placeholder
        updateAppearance(themeInfo: themeInfo)
        presentPalette()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        self.themeInfo = themeInfo
        let appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window?.appearance = appearance
        window?.backgroundColor = .clear
        containerView.themeInfo = themeInfo
        searchField.textColor = themeInfo.foreground
        searchField.backgroundColor = themeInfo.foreground.withAlphaComponent(themeInfo.isDark ? 0.06 : 0.08)
        searchField.placeholderAttributedString = NSAttributedString(
            string: mode.placeholder,
            attributes: [.foregroundColor: themeInfo.foreground.withAlphaComponent(0.45)]
        )
        tableView.appearance = appearance
        tableView.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        tableView.reloadData()
    }

    // MARK: - Private Helpers

    private func presentPalette() {
        guard let panel = window else { return }

        searchField.stringValue = ""
        selectedIndex = 0
        updateResults()
        positionPanel()

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    // MARK: - Setup

    private func setupUI() {
        guard let panel = window else { return }

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        panel.contentView = containerView

        setupSearchField()
        setupTableView()
        layoutViews()
    }

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = Mode.allItems.placeholder
        searchField.font = .systemFont(ofSize: Layout.searchFontSize)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.drawsBackground = true
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 10
        searchField.layer?.masksToBounds = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        containerView.addSubview(searchField)
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("results"))
        column.title = ""
        column.width = Layout.panelWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.rowHeight
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
    }

    private func layoutViews() {
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.panelPadding + 10),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Layout.panelPadding),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.panelPadding),
        ])
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel = window else { return }

        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            let panelHeight = computePanelHeight()
            let x = mainFrame.midX - Layout.panelWidth / 2
            let y = mainFrame.maxY - panelHeight - Layout.panelTopOffset
            panel.setFrame(NSRect(x: x, y: y, width: Layout.panelWidth, height: panelHeight), display: true)
        } else {
            let panelHeight = computePanelHeight()
            panel.setFrame(NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelHeight), display: true)
            panel.center()
        }
    }

    private func computePanelHeight() -> CGFloat {
        let visibleRows = min(results.count, Layout.maxVisibleRows)
        let tableHeight = CGFloat(max(visibleRows, 1)) * Layout.rowHeight
        let topPadding = Layout.panelPadding + 10 + Layout.searchFieldHeight + Layout.panelPadding
        return topPadding + tableHeight + Layout.panelPadding
    }

    // MARK: - Results

    private func updateResults(query: String? = nil) {
        let searchQuery = query ?? currentSearchQuery()
        results = dataSource.search(query: searchQuery)
        selectedIndex = results.isEmpty ? -1 : 0
        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
        redrawVisibleRows()

        // Resize panel to fit results
        resizePanel()
    }

    private func currentSearchQuery(from notification: Notification? = nil) -> String {
        // While the search field is actively being edited, AppKit keeps the live text in the
        // shared field editor. Reading it directly avoids stale stringValue reads in the palette panel.
        if let fieldEditor = notification?.userInfo?["NSFieldEditor"] as? NSTextView {
            return fieldEditor.string
        }
        if let fieldEditor = searchField.currentEditor() {
            return fieldEditor.string
        }
        return searchField.stringValue
    }

    private func resizePanel() {
        guard let panel = window else { return }
        let panelHeight = computePanelHeight()
        var frame = panel.frame
        let heightDiff = panelHeight - frame.height
        frame.origin.y -= heightDiff
        frame.size.height = panelHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Selection

    private func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        let item = results[selectedIndex]
        dismiss()
        onSelectItem?(item)
    }

    private func moveSelectionUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        redrawVisibleRows()
    }

    private func moveSelectionDown() {
        guard !results.isEmpty else { return }
        selectedIndex = min(results.count - 1, selectedIndex + 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        redrawVisibleRows()
    }

    private func redrawVisibleRows() {
        let rows = tableView.rows(in: tableView.visibleRect)
        guard rows.location != NSNotFound else { return }
        for row in rows.location..<(rows.location + rows.length) {
            tableView.view(atColumn: 0, row: row, makeIfNecessary: false)?.needsDisplay = true
        }
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: NSTextField) {
        confirmSelection()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        selectedIndex = row
        confirmSelection()
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        updateResults(query: currentSearchQuery(from: notification))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView.hasMarkedText() {
            return false
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelectionUp()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelectionDown()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection()
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource

extension CommandPaletteController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }
}

// MARK: - NSTableViewDelegate

extension CommandPaletteController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let item = results[row]

        let cellID = NSUserInterfaceItemIdentifier("CommandPaletteCell")
        let cell: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = makeCell(identifier: cellID)
        }

        // Configure icon
        if let iconName = item.iconName {
            cell.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            cell.imageView?.contentTintColor = themeInfo.foreground.withAlphaComponent(0.65)
        } else {
            cell.imageView?.image = nil
        }

        // Configure text
        cell.textField?.stringValue = item.title
        cell.textField?.textColor = themeInfo.foreground

        // Configure subtitle (second text field, tag 100)
        if let paletteCell = cell as? PaletteCellView {
            paletteCell.themeInfo = themeInfo
        }

        if let subtitleField = cell.viewWithTag(100) as? NSTextField {
            subtitleField.stringValue = item.subtitle ?? ""
            subtitleField.textColor = themeInfo.foreground.withAlphaComponent(0.58)
            subtitleField.isHidden = item.subtitle == nil
        }

        // Configure shortcut hint (third text field, tag 101)
        if let shortcutField = cell.viewWithTag(101) as? NSTextField {
            shortcutField.stringValue = item.shortcutHint ?? ""
            shortcutField.textColor = themeInfo.foreground.withAlphaComponent(0.45)
            shortcutField.isHidden = item.shortcutHint == nil
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 {
            selectedIndex = row
        }
        redrawVisibleRows()
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = PaletteCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        cell.addSubview(imageView)
        cell.imageView = imageView

        let titleField = NSTextField(labelWithString: "")
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: Layout.titleFontSize)
        titleField.textColor = themeInfo.foreground
        titleField.lineBreakMode = .byTruncatingTail
        cell.addSubview(titleField)
        cell.textField = titleField

        let subtitleField = NSTextField(labelWithString: "")
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = .systemFont(ofSize: Layout.subtitleFontSize)
        subtitleField.textColor = themeInfo.foreground.withAlphaComponent(0.58)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.tag = 100
        cell.addSubview(subtitleField)

        let shortcutField = NSTextField(labelWithString: "")
        shortcutField.translatesAutoresizingMaskIntoConstraints = false
        shortcutField.font = .monospacedSystemFont(ofSize: Layout.shortcutFontSize, weight: .regular)
        shortcutField.textColor = themeInfo.foreground.withAlphaComponent(0.45)
        shortcutField.alignment = .right
        shortcutField.tag = 101
        cell.addSubview(shortcutField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.cellLeadingPadding),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),

            titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Layout.cellSpacing),
            titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: Layout.cellSpacing),
            subtitleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            shortcutField.leadingAnchor.constraint(greaterThanOrEqualTo: subtitleField.trailingAnchor, constant: Layout.cellSpacing),
            shortcutField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Layout.cellTrailingPadding),
            shortcutField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleField.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        shortcutField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return cell
    }
}

private final class PaletteSearchField: NSTextField {
    override class var cellClass: AnyClass? {
        get { PaletteSearchFieldCell.self }
        set {}
    }
}

private final class PaletteSearchFieldCell: NSTextFieldCell {
    private let insets = NSSize(width: 12, height: 0)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: insets.width, dy: insets.height)
    }


    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: rect).insetBy(dx: insets.width, dy: insets.height)
    }
}

private final class PaletteContainerView: NSView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        themeInfo.background.withAlphaComponent(themeInfo.isDark ? 0.96 : 0.98).setFill()
        path.fill()
        themeInfo.foreground.withAlphaComponent(themeInfo.isDark ? 0.14 : 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class PaletteCellView: NSTableCellView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            let selectionRect = bounds.insetBy(dx: 0, dy: 3)
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 9, yRadius: 9)
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
            accent.withAlphaComponent(themeInfo.isDark ? 0.34 : 0.22).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }

    private var isSelectedRow: Bool {
        guard let tableView = enclosingScrollView?.documentView as? NSTableView else { return false }
        return tableView.selectedRow == tableView.row(for: self)
    }
}
