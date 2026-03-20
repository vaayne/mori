import AppKit
import MoriCore
import MoriGit

/// NSWindowController managing a floating worktree creation panel.
/// Contains a search field for branch filtering, a table view for branch selection,
/// and a footer bar with base branch, template, and path preview.
@MainActor
final class WorktreeCreationController: NSWindowController {

    // MARK: - Callbacks

    /// Called when the user confirms worktree creation.
    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?

    /// Called to fetch branches asynchronously. Caller provides this closure
    /// so the controller has no direct GitBackend dependency.
    var fetchBranches: ((_ repoPath: String) async throws -> [GitBranchInfo])?

    // MARK: - State

    private var dataSource: WorktreeCreationDataSource?
    private var rows: [BranchRow] = []
    private var selectedIndex: Int = -1
    private var isNewBranchMode: Bool = false
    private var projectName: String = ""
    private var projectId: UUID?
    private var repoPath: String = ""
    nonisolated(unsafe) private var localEventMonitor: Any?

    // MARK: - Views

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let tableSeparator = NSBox()

    // Footer views
    private let footerContainer = NSView()
    private let footerSeparator = NSBox()
    private let baseBranchField = NSTextField()
    private let templatePopup = NSPopUpButton()
    private let pathLabel = NSTextField(labelWithString: "")
    private var footerHeightConstraint: NSLayoutConstraint!
    private var footerControlsContainer = NSView()

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 500
        static let searchFieldHeight: CGFloat = 36
        static let branchRowHeight: CGFloat = 32
        static let sectionHeaderHeight: CGFloat = 24
        static let maxVisibleRows: Int = 10
        static let panelPadding: CGFloat = 8
        static let fieldHorizontalPadding: CGFloat = 12
        static let cellIconSize: CGFloat = 18
        static let cellLeadingPadding: CGFloat = 8
        static let cellSpacing: CGFloat = 8
        static let cellTrailingPadding: CGFloat = 8
        static let titleFontSize: CGFloat = 13
        static let subtitleFontSize: CGFloat = 11
        static let searchFontSize: CGFloat = 16
        static let panelTopOffset: CGFloat = 80
        static let footerCollapsedHeight: CGFloat = 28
        static let footerExpandedHeight: CGFloat = 56
        static let sectionHeaderFontSize: CGFloat = 10
        static let timeFontSize: CGFloat = 11
        static let badgeFontSize: CGFloat = 10
        static let pathFontSize: CGFloat = 11
    }

    // MARK: - Init

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true

        super.init(window: panel)

        setupUI()
        setupKeyEventMonitor()
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Show the panel for a given project, pre-loading branch data.
    func show(
        projectId: UUID,
        projectName: String,
        repoPath: String,
        existingBranches: Set<String>
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.repoPath = repoPath

        // Reset state
        searchField.stringValue = ""
        selectedIndex = -1
        isNewBranchMode = false
        rows = []
        dataSource = nil
        updateFooterVisibility(animated: false)
        tableView.reloadData()

        // Position and show
        positionPanel()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)

        // Fetch branches asynchronously
        Task { [weak self] in
            guard let self else { return }
            do {
                let branches = try await self.fetchBranches?(repoPath) ?? []
                self.dataSource = WorktreeCreationDataSource(
                    branches: branches,
                    existingBranchNames: existingBranches
                )
                self.updateResults()
            } catch {
                // On failure, show empty state — user can dismiss and retry
                self.dataSource = WorktreeCreationDataSource(
                    branches: [],
                    existingBranchNames: existingBranches
                )
                self.updateResults()
            }
        }
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    // MARK: - Setup

    private func setupUI() {
        guard let panel = window else { return }

        containerView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = containerView

        setupSearchField()
        setupTableView()
        setupFooter()
        layoutViews()

        // Tab key view chain for footer controls
        baseBranchField.nextKeyView = templatePopup
        templatePopup.nextKeyView = searchField
    }

    /// Monitor for keyboard events when non-text controls (e.g., templatePopup) have focus.
    private func setupKeyEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.window, panel.isVisible else { return event }
            let firstResponder = panel.firstResponder

            // Handle Esc from template popup — return to search field
            if event.keyCode == 53 { // Esc
                if firstResponder === self.templatePopup || firstResponder === self.templatePopup.window {
                    if self.isNewBranchMode {
                        self.exitNewBranchMode()
                        return nil
                    }
                }
            }

            // Handle Enter from template popup — confirm selection
            if event.keyCode == 36 { // Return
                if firstResponder === self.templatePopup {
                    self.confirmSelection()
                    return nil
                }
            }

            return event
        }
    }

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = .localized("Search branches...")
        searchField.font = .systemFont(ofSize: Layout.searchFontSize)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.isBezeled = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        containerView.addSubview(searchField)
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branches"))
        column.title = ""
        column.width = Layout.panelWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.branchRowHeight
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        containerView.addSubview(scrollView)
    }

    private func setupFooter() {
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(footerContainer)

        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .separator
        footerContainer.addSubview(footerSeparator)

        // Controls row (base branch + template) — only visible in new branch mode
        footerControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        footerControlsContainer.isHidden = true
        footerContainer.addSubview(footerControlsContainer)

        // Base branch label + field
        let fromLabel = NSTextField(labelWithString: .localized("from:"))
        fromLabel.translatesAutoresizingMaskIntoConstraints = false
        fromLabel.font = .systemFont(ofSize: Layout.subtitleFontSize)
        fromLabel.textColor = .secondaryLabelColor
        footerControlsContainer.addSubview(fromLabel)

        baseBranchField.translatesAutoresizingMaskIntoConstraints = false
        baseBranchField.placeholderString = "main"
        baseBranchField.font = .systemFont(ofSize: Layout.subtitleFontSize)
        baseBranchField.isBordered = true
        baseBranchField.bezelStyle = .roundedBezel
        baseBranchField.focusRingType = .none
        baseBranchField.delegate = self
        footerControlsContainer.addSubview(baseBranchField)

        // Template label + popup
        let templateLabel = NSTextField(labelWithString: .localized("Template:"))
        templateLabel.translatesAutoresizingMaskIntoConstraints = false
        templateLabel.font = .systemFont(ofSize: Layout.subtitleFontSize)
        templateLabel.textColor = .secondaryLabelColor
        footerControlsContainer.addSubview(templateLabel)

        templatePopup.translatesAutoresizingMaskIntoConstraints = false
        templatePopup.font = .systemFont(ofSize: Layout.subtitleFontSize)
        templatePopup.removeAllItems()
        for template in TemplateRegistry.all {
            templatePopup.addItem(withTitle: template.name.capitalized)
        }
        templatePopup.controlSize = .small
        footerControlsContainer.addSubview(templatePopup)

        // Path preview
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: Layout.pathFontSize)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        footerContainer.addSubview(pathLabel)

        // Layout controls row
        NSLayoutConstraint.activate([
            fromLabel.leadingAnchor.constraint(equalTo: footerControlsContainer.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            fromLabel.centerYAnchor.constraint(equalTo: footerControlsContainer.centerYAnchor),

            baseBranchField.leadingAnchor.constraint(equalTo: fromLabel.trailingAnchor, constant: 4),
            baseBranchField.centerYAnchor.constraint(equalTo: footerControlsContainer.centerYAnchor),
            baseBranchField.widthAnchor.constraint(equalToConstant: 120),

            templateLabel.leadingAnchor.constraint(equalTo: baseBranchField.trailingAnchor, constant: 16),
            templateLabel.centerYAnchor.constraint(equalTo: footerControlsContainer.centerYAnchor),

            templatePopup.leadingAnchor.constraint(equalTo: templateLabel.trailingAnchor, constant: 4),
            templatePopup.centerYAnchor.constraint(equalTo: footerControlsContainer.centerYAnchor),
            templatePopup.trailingAnchor.constraint(lessThanOrEqualTo: footerControlsContainer.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
        ])

        // Layout footer container
        footerHeightConstraint = footerContainer.heightAnchor.constraint(equalToConstant: Layout.footerCollapsedHeight)
        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),

            footerControlsContainer.topAnchor.constraint(equalTo: footerSeparator.bottomAnchor, constant: 4),
            footerControlsContainer.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerControlsContainer.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footerControlsContainer.heightAnchor.constraint(equalToConstant: 22),

            pathLabel.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor, constant: -4),
            pathLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            pathLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -Layout.fieldHorizontalPadding),

            footerHeightConstraint,
        ])
    }

    private func layoutViews() {
        tableSeparator.translatesAutoresizingMaskIntoConstraints = false
        tableSeparator.boxType = .separator
        containerView.addSubview(tableSeparator)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.panelPadding),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),

            tableSeparator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Layout.panelPadding),
            tableSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: tableSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            footerContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
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
        var totalRowHeight: CGFloat = 0
        let visibleCount = min(rows.count, Layout.maxVisibleRows)
        for i in 0..<visibleCount {
            totalRowHeight += rowHeight(for: i)
        }
        if visibleCount == 0 {
            totalRowHeight = Layout.branchRowHeight // minimum height
        }
        let topPadding = Layout.panelPadding + Layout.searchFieldHeight + Layout.panelPadding + 1
        let footerHeight = isNewBranchMode ? Layout.footerExpandedHeight : Layout.footerCollapsedHeight
        return topPadding + totalRowHeight + footerHeight
    }

    private func rowHeight(for index: Int) -> CGFloat {
        guard index < rows.count else { return Layout.branchRowHeight }
        if rows[index].isSectionHeader {
            return Layout.sectionHeaderHeight
        }
        return Layout.branchRowHeight
    }

    // MARK: - Results

    private func updateResults() {
        let query = searchField.stringValue
        rows = dataSource?.filteredRows(query: query) ?? []

        // Find first selectable row
        selectedIndex = firstSelectableIndex(from: 0)

        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        updatePathPreview()
        resizePanel()
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

    private func firstSelectableIndex(from start: Int) -> Int {
        for i in start..<rows.count {
            if !rows[i].isSectionHeader { return i }
        }
        return -1
    }

    private func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < rows.count else { return }
        let row = rows[selectedIndex]

        switch row {
        case .createNewBranch(let name):
            if isNewBranchMode {
                // Second Enter — create with base branch
                let baseBranch = baseBranchField.stringValue.isEmpty
                    ? (dataSource?.defaultBaseBranch ?? "main")
                    : baseBranchField.stringValue
                let template = selectedTemplate()
                dismiss()
                onCreateWorktree?(WorktreeCreationRequest(
                    branchName: name,
                    isNewBranch: true,
                    baseBranch: baseBranch,
                    template: template
                ))
            } else {
                // First Enter — enter two-phase mode
                enterNewBranchMode()
            }

        case .branch(let info, _):
            let branchName = info.isRemote ? info.displayName : info.name
            let template = selectedTemplate()
            dismiss()
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: branchName,
                isNewBranch: false,
                baseBranch: nil,
                template: template
            ))

        case .sectionHeader:
            break
        }
    }

    private func enterNewBranchMode() {
        isNewBranchMode = true
        baseBranchField.stringValue = dataSource?.defaultBaseBranch ?? "main"
        updateFooterVisibility(animated: true)
        resizePanel()
        // Move focus to base branch field
        window?.makeFirstResponder(baseBranchField)
    }

    private func exitNewBranchMode() {
        isNewBranchMode = false
        updateFooterVisibility(animated: true)
        resizePanel()
        window?.makeFirstResponder(searchField)
    }

    private func moveSelectionUp() {
        guard !rows.isEmpty, selectedIndex > 0 else { return }
        var next = selectedIndex - 1
        // Skip section headers
        while next >= 0 && rows[next].isSectionHeader {
            next -= 1
        }
        if next >= 0 {
            selectedIndex = next
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
            updatePathPreview()
        }
    }

    private func moveSelectionDown() {
        guard !rows.isEmpty, selectedIndex < rows.count - 1 else { return }
        var next = selectedIndex + 1
        // Skip section headers
        while next < rows.count && rows[next].isSectionHeader {
            next += 1
        }
        if next < rows.count {
            selectedIndex = next
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
            updatePathPreview()
        }
    }

    // MARK: - Footer

    private func updateFooterVisibility(animated: Bool) {
        let newHeight = isNewBranchMode ? Layout.footerExpandedHeight : Layout.footerCollapsedHeight
        footerControlsContainer.isHidden = !isNewBranchMode

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                self.footerHeightConstraint.constant = newHeight
                self.containerView.layoutSubtreeIfNeeded()
            }
        } else {
            footerHeightConstraint.constant = newHeight
        }
    }

    private func updatePathPreview() {
        guard selectedIndex >= 0, selectedIndex < rows.count else {
            pathLabel.stringValue = ""
            return
        }
        let row = rows[selectedIndex]
        let branchName: String?
        switch row {
        case .createNewBranch(let name):
            branchName = name
        case .branch(let info, _):
            branchName = info.isRemote ? info.displayName : info.name
        case .sectionHeader:
            branchName = nil
        }
        if let name = branchName {
            pathLabel.stringValue = WorktreeCreationDataSource.previewPath(
                projectName: projectName,
                branchName: name
            )
        } else {
            pathLabel.stringValue = ""
        }
    }

    private func selectedTemplate() -> SessionTemplate {
        let index = templatePopup.indexOfSelectedItem
        guard index >= 0, index < TemplateRegistry.all.count else {
            return TemplateRegistry.basic
        }
        return TemplateRegistry.all[index]
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: NSTextField) {
        confirmSelection()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, !rows[row].isSectionHeader else { return }
        selectedIndex = row
        confirmSelection()
    }
}

// MARK: - NSTextFieldDelegate

extension WorktreeCreationController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === searchField {
            // Exit new branch mode when search text changes
            if isNewBranchMode {
                exitNewBranchMode()
            }
            updateResults()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField {
            return handleSearchFieldCommand(commandSelector)
        }
        if control === baseBranchField {
            return handleBaseBranchFieldCommand(commandSelector)
        }
        return false
    }

    private func handleSearchFieldCommand(_ commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelectionUp()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelectionDown()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // First Esc exits new-branch mode; second Esc dismisses panel
            if isNewBranchMode {
                exitNewBranchMode()
            } else {
                dismiss()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if isNewBranchMode {
                window?.makeFirstResponder(baseBranchField)
                return true
            }
        }
        return false
    }

    private func handleBaseBranchFieldCommand(_ commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            exitNewBranchMode()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            window?.makeFirstResponder(templatePopup)
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            window?.makeFirstResponder(searchField)
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource

extension WorktreeCreationController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }
}

// MARK: - NSTableViewDelegate

extension WorktreeCreationController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight(for: row)
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard row < rows.count else { return false }
        return rows[row].isSectionHeader
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < rows.count else { return false }
        return !rows[row].isSectionHeader
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let item = rows[row]

        switch item {
        case .sectionHeader(let section):
            return makeSectionHeaderView(section: section, tableView: tableView)
        case .createNewBranch(let name):
            return makeBranchCellView(
                icon: "plus.circle",
                title: "\(String.localized("Create")) \"\(name)\"",
                subtitle: nil,
                inUse: false,
                isCreateNew: true,
                tableView: tableView
            )
        case .branch(let info, let inUse):
            let icon = info.isRemote ? "cloud" : "arrow.branch"
            let subtitle = info.commitDate.map { relativeTimeString(from: $0) }
            let displayTitle: String
            if info.isRemote {
                displayTitle = info.displayName
            } else if info.isHead {
                displayTitle = "\(info.name) *"
            } else {
                displayTitle = info.name
            }
            return makeBranchCellView(
                icon: icon,
                title: displayTitle,
                subtitle: subtitle,
                inUse: inUse,
                isCreateNew: false,
                tableView: tableView
            )
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < rows.count, !rows[row].isSectionHeader {
            selectedIndex = row
            updatePathPreview()
        }
    }

    // MARK: - Cell Factories

    private func makeSectionHeaderView(section: BranchSection, tableView: NSTableView) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("SectionHeader")
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            existing.textField?.stringValue = sectionTitle(for: section)
            return existing
        }

        let cell = NSTableCellView()
        cell.identifier = cellID

        let label = NSTextField(labelWithString: sectionTitle(for: section))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Layout.sectionHeaderFontSize, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.cellLeadingPadding),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makeBranchCellView(
        icon: String,
        title: String,
        subtitle: String?,
        inUse: Bool,
        isCreateNew: Bool = false,
        tableView: NSTableView
    ) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("BranchCell")
        let cell: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = makeBranchCell(identifier: cellID)
        }

        // Configure icon
        cell.imageView?.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        if isCreateNew {
            cell.imageView?.contentTintColor = .systemGreen
        } else if inUse {
            cell.imageView?.contentTintColor = .tertiaryLabelColor
        } else {
            cell.imageView?.contentTintColor = .secondaryLabelColor
        }

        // Configure title
        cell.textField?.stringValue = title
        if isCreateNew {
            cell.textField?.textColor = .labelColor
        } else if inUse {
            cell.textField?.textColor = .tertiaryLabelColor
        } else {
            cell.textField?.textColor = .labelColor
        }

        // Configure subtitle (tag 100 — relative time)
        if let timeField = cell.viewWithTag(100) as? NSTextField {
            timeField.stringValue = subtitle ?? ""
            timeField.isHidden = subtitle == nil
        }

        // Configure "in use" badge (tag 101)
        if let badgeField = cell.viewWithTag(101) as? NSTextField {
            badgeField.stringValue = inUse ? .localized("in use") : ""
            badgeField.isHidden = !inUse
        }

        return cell
    }

    private func makeBranchCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        cell.addSubview(imageView)
        cell.imageView = imageView

        let titleField = NSTextField(labelWithString: "")
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: Layout.titleFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        cell.addSubview(titleField)
        cell.textField = titleField

        let timeField = NSTextField(labelWithString: "")
        timeField.translatesAutoresizingMaskIntoConstraints = false
        timeField.font = .systemFont(ofSize: Layout.timeFontSize)
        timeField.textColor = .tertiaryLabelColor
        timeField.tag = 100
        cell.addSubview(timeField)

        let badgeField = NSTextField(labelWithString: "")
        badgeField.translatesAutoresizingMaskIntoConstraints = false
        badgeField.font = .systemFont(ofSize: Layout.badgeFontSize, weight: .medium)
        badgeField.textColor = .tertiaryLabelColor
        badgeField.tag = 101
        cell.addSubview(badgeField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.cellLeadingPadding),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),

            titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Layout.cellSpacing),
            titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            timeField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: Layout.cellSpacing),
            timeField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            badgeField.leadingAnchor.constraint(greaterThanOrEqualTo: timeField.trailingAnchor, constant: Layout.cellSpacing),
            badgeField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Layout.cellTrailingPadding),
            badgeField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        badgeField.setContentCompressionResistancePriority(.required, for: .horizontal)

        return cell
    }

    // MARK: - Helpers

    private func sectionTitle(for section: BranchSection) -> String {
        switch section {
        case .createNew: return .localized("CREATE NEW BRANCH")
        case .local: return .localized("LOCAL")
        case .remote: return .localized("REMOTE")
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let seconds = Int(interval)
        if seconds < 60 { return .localized("now") }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        let years = days / 365
        return "\(years)y ago"
    }
}
