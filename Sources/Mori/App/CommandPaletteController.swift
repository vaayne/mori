import AppKit
import MoriCore
import MoriTerminal

/// NSWindowController managing a floating command palette panel.
/// Contains an NSTextField for search and an NSTableView for results.
@MainActor
final class CommandPaletteController: NSWindowController, ThemedSurface {

    var themedWindow: NSWindow? { nil }

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
    private let blurView = PaletteBlurView()
    private let tintView = PaletteTintView()
    private let searchIconView = NSImageView()
    private let separatorView = PaletteSeparatorView()
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
        static let searchAreaHeight: CGFloat = 48
        static let searchIconSize: CGFloat = 15
        static let searchIconLeading: CGFloat = 20
        static let searchTextSpacing: CGFloat = 9
        static let separatorHeight: CGFloat = 0.5
        static let listTopPadding: CGFloat = 4
        static let listHorizontalInset: CGFloat = 8
        static let listBottomInset: CGFloat = 8
        static let rowHeight: CGFloat = 34
        static let maxVisibleRows: Int = 10
        static let cellIconSize: CGFloat = 16
        static let cellLeadingPadding: CGFloat = 12
        static let cellSpacing: CGFloat = 10
        static let cellTrailingPadding: CGFloat = 8
        static let titleFontSize: CGFloat = 13
        static let subtitleFontSize: CGFloat = 11
        static let shortcutFontSize: CGFloat = 11
        static let searchFontSize: CGFloat = 16
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
        applyTheme(themeInfo)
        presentPalette()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

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
        panel.contentView = containerView

        setupBackground()
        setupSearchField()
        setupTableView()
        layoutViews()
    }

    private func setupBackground() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.blendingMode = .behindWindow
        blurView.material = .popover
        blurView.state = .active
        containerView.addSubview(blurView)

        tintView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tintView)
    }

    private func setupSearchField() {
        searchIconView.translatesAutoresizingMaskIntoConstraints = false
        searchIconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIconView.imageScaling = .scaleProportionallyDown
        containerView.addSubview(searchIconView)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = Mode.allItems.placeholder
        searchField.font = .systemFont(ofSize: Layout.searchFontSize)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        containerView.addSubview(searchField)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separatorView)
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
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.listBottomInset),
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
        return Layout.searchAreaHeight + Layout.separatorHeight + Layout.listTopPadding + tableHeight + Layout.listBottomInset
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
        tableView.noteNumberOfRowsChanged()
        if selectedIndex >= 0 {
            tableView.setNeedsDisplay(tableView.rect(ofRow: selectedIndex))
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

        // Configure trailing hint (third text field, tag 101)
        if let hintField = cell.viewWithTag(101) as? NSTextField {
            if let shortcutHint = item.shortcutHint {
                hintField.stringValue = shortcutHint
                hintField.font = .monospacedSystemFont(ofSize: Layout.shortcutFontSize, weight: .regular)
                hintField.textColor = themeInfo.foreground.withAlphaComponent(0.45)
                hintField.isHidden = false
            } else if let typeLabel = item.typeLabel {
                hintField.stringValue = typeLabel
                hintField.font = .systemFont(ofSize: Layout.shortcutFontSize)
                hintField.textColor = themeInfo.foreground.withAlphaComponent(0.4)
                hintField.isHidden = false
            } else {
                hintField.stringValue = ""
                hintField.isHidden = true
            }
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

        let hintField = NSTextField(labelWithString: "")
        hintField.translatesAutoresizingMaskIntoConstraints = false
        hintField.font = .monospacedSystemFont(ofSize: Layout.shortcutFontSize, weight: .regular)
        hintField.textColor = themeInfo.foreground.withAlphaComponent(0.45)
        hintField.alignment = .right
        hintField.tag = 101
        cell.addSubview(hintField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.cellLeadingPadding),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),

            titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Layout.cellSpacing),
            titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: Layout.cellSpacing),
            subtitleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            hintField.leadingAnchor.constraint(greaterThanOrEqualTo: subtitleField.trailingAnchor, constant: Layout.cellSpacing),
            hintField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Layout.cellTrailingPadding),
            hintField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleField.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        hintField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return cell
    }
}

private final class PaletteSearchField: NSTextField {}

private final class PaletteContainerView: NSView {}

private final class PaletteBlurView: NSVisualEffectView {
    override func layout() {
        super.layout()
        maskImage = NSImage.roundedMask(size: bounds.size, radius: 14)
    }
}

private final class PaletteTintView: NSView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        themeInfo.background.withAlphaComponent(themeInfo.isDark ? 0.55 : 0.65).setFill()
        path.fill()
        themeInfo.foreground.withAlphaComponent(themeInfo.isDark ? 0.14 : 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class PaletteSeparatorView: NSView {
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

private extension NSImage {
    static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
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

private final class PaletteCellView: NSTableCellView {
    var themeInfo: GhosttyThemeInfo = .fallback {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            let selectionRect = bounds.insetBy(dx: 0, dy: 2)
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
            accent.withAlphaComponent(themeInfo.isDark ? 0.4 : 0.28).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }

    private var isSelectedRow: Bool {
        guard let tableView = enclosingScrollView?.documentView as? NSTableView else { return false }
        return tableView.selectedRow == tableView.row(for: self)
    }
}
