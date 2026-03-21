import AppKit
import MoriCore
import MoriGit

/// NSWindowController managing a floating worktree creation panel.
///
/// Design: The search field is the primary input. As you type, autocomplete suggestions
/// filter below. Enter creates from the typed name — if it matches an existing branch,
/// uses it; otherwise creates a new branch from the base. No modes, no phases.
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
    private var suggestions: [BranchSuggestion] = []
    private var selectedIndex: Int = -1
    private var projectName: String = ""
    private var projectId: UUID?
    private var repoPath: String = ""
    /// Incremented on each show() to invalidate stale async branch fetches.
    private var fetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // MARK: - Views

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let tableSeparator = NSBox()
    /// Shows "✓ exists" or "✚ new" badge next to the search field.
    private let statusBadge = NSTextField(labelWithString: "")

    // Footer views
    private let footerContainer = NSView()
    private let footerSeparator = NSBox()
    private let baseBranchField = NSTextField()
    private let templatePopup = NSPopUpButton()
    private let pathLabel = NSTextField(labelWithString: "")

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 500
        static let searchFieldHeight: CGFloat = 36
        static let rowHeight: CGFloat = 32
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
        static let footerHeight: CGFloat = 56
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
        suggestions = []
        dataSource = nil
        baseBranchField.stringValue = ""
        templatePopup.selectItem(at: 0)
        tableView.reloadData()
        updateStatusBadge()
        updatePathPreview()

        // Position and show
        positionPanel()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)

        // Fetch branches asynchronously
        fetchGeneration += 1
        let currentGeneration = fetchGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let branches = try await self.fetchBranches?(repoPath) ?? []
                guard self.fetchGeneration == currentGeneration else { return }
                self.dataSource = WorktreeCreationDataSource(
                    branches: branches,
                    existingBranchNames: existingBranches
                )
                self.baseBranchField.placeholderString = self.dataSource?.defaultBaseBranch ?? "main"
                self.updateResults()
            } catch {
                guard self.fetchGeneration == currentGeneration else { return }
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

        // Tab key view chain
        searchField.nextKeyView = baseBranchField
        baseBranchField.nextKeyView = templatePopup
        templatePopup.nextKeyView = searchField
    }

    private func setupKeyEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.window, panel.isVisible else { return event }
            let firstResponder = panel.firstResponder

            // Handle Enter from template popup — confirm
            if event.keyCode == 36, firstResponder === self.templatePopup {
                self.confirmInput()
                return nil
            }

            // Handle Esc from template popup — back to search
            if event.keyCode == 53, firstResponder === self.templatePopup {
                panel.makeFirstResponder(self.searchField)
                return nil
            }

            return event
        }
    }

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = .localized("Branch name...")
        searchField.font = .systemFont(ofSize: Layout.searchFontSize)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.isBezeled = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        containerView.addSubview(searchField)

        // Status badge (right side of search field area)
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.font = .systemFont(ofSize: Layout.badgeFontSize, weight: .medium)
        statusBadge.alignment = .right
        statusBadge.isEditable = false
        statusBadge.isBordered = false
        statusBadge.backgroundColor = .clear
        containerView.addSubview(statusBadge)
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branches"))
        column.title = ""
        column.width = Layout.panelWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.rowHeight
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

        // Base branch label + field
        let fromLabel = NSTextField(labelWithString: .localized("Base:"))
        fromLabel.translatesAutoresizingMaskIntoConstraints = false
        fromLabel.font = .systemFont(ofSize: Layout.subtitleFontSize)
        fromLabel.textColor = .secondaryLabelColor
        footerContainer.addSubview(fromLabel)

        baseBranchField.translatesAutoresizingMaskIntoConstraints = false
        baseBranchField.placeholderString = "main"
        baseBranchField.font = .systemFont(ofSize: Layout.subtitleFontSize)
        baseBranchField.isBordered = true
        baseBranchField.bezelStyle = .roundedBezel
        baseBranchField.focusRingType = .none
        baseBranchField.delegate = self
        footerContainer.addSubview(baseBranchField)

        // Template label + popup
        let templateLabel = NSTextField(labelWithString: .localized("Template:"))
        templateLabel.translatesAutoresizingMaskIntoConstraints = false
        templateLabel.font = .systemFont(ofSize: Layout.subtitleFontSize)
        templateLabel.textColor = .secondaryLabelColor
        footerContainer.addSubview(templateLabel)

        templatePopup.translatesAutoresizingMaskIntoConstraints = false
        templatePopup.font = .systemFont(ofSize: Layout.subtitleFontSize)
        templatePopup.removeAllItems()
        for template in TemplateRegistry.all {
            templatePopup.addItem(withTitle: template.name.capitalized)
        }
        templatePopup.controlSize = .small
        templatePopup.target = self
        templatePopup.action = #selector(templateChanged(_:))
        footerContainer.addSubview(templatePopup)

        // Path preview
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: Layout.pathFontSize)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        footerContainer.addSubview(pathLabel)

        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),

            fromLabel.topAnchor.constraint(equalTo: footerSeparator.bottomAnchor, constant: 6),
            fromLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.fieldHorizontalPadding),

            baseBranchField.leadingAnchor.constraint(equalTo: fromLabel.trailingAnchor, constant: 4),
            baseBranchField.centerYAnchor.constraint(equalTo: fromLabel.centerYAnchor),
            baseBranchField.widthAnchor.constraint(equalToConstant: 120),

            templateLabel.leadingAnchor.constraint(equalTo: baseBranchField.trailingAnchor, constant: 16),
            templateLabel.centerYAnchor.constraint(equalTo: fromLabel.centerYAnchor),

            templatePopup.leadingAnchor.constraint(equalTo: templateLabel.trailingAnchor, constant: 4),
            templatePopup.centerYAnchor.constraint(equalTo: fromLabel.centerYAnchor),
            templatePopup.trailingAnchor.constraint(lessThanOrEqualTo: footerContainer.trailingAnchor, constant: -Layout.fieldHorizontalPadding),

            pathLabel.topAnchor.constraint(equalTo: fromLabel.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            pathLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: footerContainer.bottomAnchor, constant: -4),

            footerContainer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
        ])
    }

    private func layoutViews() {
        tableSeparator.translatesAutoresizingMaskIntoConstraints = false
        tableSeparator.boxType = .separator
        containerView.addSubview(tableSeparator)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.panelPadding),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.fieldHorizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),

            statusBadge.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            statusBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.fieldHorizontalPadding),
            statusBadge.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            statusBadge.widthAnchor.constraint(equalToConstant: 64),

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
        let visibleRows = min(suggestions.count, Layout.maxVisibleRows)
        let tableHeight = CGFloat(max(visibleRows, 1)) * Layout.rowHeight
        let topPadding = Layout.panelPadding + Layout.searchFieldHeight + Layout.panelPadding + 1
        return topPadding + tableHeight + Layout.footerHeight
    }

    // MARK: - Results

    private func updateResults() {
        let query = searchField.stringValue
        suggestions = dataSource?.filteredSuggestions(query: query) ?? []
        selectedIndex = suggestions.isEmpty ? -1 : 0

        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        updateStatusBadge()
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

    // MARK: - Confirm

    /// The main action. Determines whether to use an existing branch or create new.
    private func confirmInput() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        let template = selectedTemplate()

        // Check: is a suggestion selected (user arrowed down into the list)?
        if selectedIndex >= 0, selectedIndex < suggestions.count {
            let suggestion = suggestions[selectedIndex]
            let info = suggestion.info
            // If the selected suggestion's name matches the query, use it as existing
            let matchName = info.isRemote ? info.displayName : info.name
            if matchName.lowercased() == query.lowercased() {
                dismiss()
                onCreateWorktree?(WorktreeCreationRequest(
                    branchName: info.name,
                    isNewBranch: false,
                    baseBranch: nil,
                    template: template
                ))
                return
            }
        }

        // Check: does the typed text exactly match any branch?
        if let match = dataSource?.exactMatch(for: query) {
            dismiss()
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: match.name,
                isNewBranch: false,
                baseBranch: nil,
                template: template
            ))
            return
        }

        // No match — create new branch
        let baseBranch = baseBranchField.stringValue.isEmpty
            ? (dataSource?.defaultBaseBranch ?? "main")
            : baseBranchField.stringValue
        dismiss()
        onCreateWorktree?(WorktreeCreationRequest(
            branchName: query,
            isNewBranch: true,
            baseBranch: baseBranch,
            template: template
        ))
    }

    /// When user arrows into a suggestion and presses Enter, use that suggestion directly.
    private func confirmSuggestion() {
        guard selectedIndex >= 0, selectedIndex < suggestions.count else {
            confirmInput()
            return
        }

        let suggestion = suggestions[selectedIndex]
        let template = selectedTemplate()
        dismiss()
        onCreateWorktree?(WorktreeCreationRequest(
            branchName: suggestion.info.name,
            isNewBranch: false,
            baseBranch: nil,
            template: template
        ))
    }

    private func moveSelectionUp() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        updatePathPreview()
    }

    private func moveSelectionDown() {
        guard !suggestions.isEmpty else { return }
        if selectedIndex < suggestions.count - 1 {
            selectedIndex += 1
        }
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        updatePathPreview()
    }

    // MARK: - Status & Footer

    private func updateStatusBadge() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            statusBadge.stringValue = ""
            return
        }

        if dataSource?.exactMatch(for: query) != nil {
            statusBadge.stringValue = "✓ exists"
            statusBadge.textColor = .systemBlue
        } else {
            statusBadge.stringValue = "✚ new"
            statusBadge.textColor = .systemGreen
        }
    }

    private func updatePathPreview() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            pathLabel.stringValue = ""
            return
        }

        // Determine the effective branch name for path preview
        let branchForPath: String
        if let match = dataSource?.exactMatch(for: query) {
            branchForPath = match.isRemote ? match.displayName : match.name
        } else {
            branchForPath = query
        }

        let path = WorktreeCreationDataSource.previewPath(
            projectName: projectName,
            branchName: branchForPath
        )
        let template = selectedTemplate()

        var preview = "\(String.localized("Path:")) \(path)"

        // Show base branch info for new branches
        if dataSource?.exactMatch(for: query) == nil {
            let base = baseBranchField.stringValue.isEmpty
                ? (dataSource?.defaultBaseBranch ?? "main")
                : baseBranchField.stringValue
            preview += "  \(String.localized("from:")) \(base)"
        }

        if template.name != "basic" {
            preview += "  [\(template.name.capitalized)]"
        }
        pathLabel.stringValue = preview
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
        confirmInput()
    }

    @objc private func templateChanged(_ sender: NSPopUpButton) {
        updatePathPreview()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < suggestions.count else { return }
        selectedIndex = row
        confirmSuggestion()
    }
}

// MARK: - NSTextFieldDelegate

extension WorktreeCreationController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === searchField {
            updateResults()
        } else if field === baseBranchField {
            updatePathPreview()
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
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmInput()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            window?.makeFirstResponder(baseBranchField)
            return true
        }
        return false
    }

    private func handleBaseBranchFieldCommand(_ commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.makeFirstResponder(searchField)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmInput()
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
        suggestions.count
    }
}

// MARK: - NSTableViewDelegate

extension WorktreeCreationController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < suggestions.count else { return nil }
        let suggestion = suggestions[row]
        let info = suggestion.info

        let icon = info.isRemote ? "cloud" : "arrow.branch"
        let displayTitle: String
        if info.isRemote {
            displayTitle = info.displayName
        } else if info.isHead {
            displayTitle = "\(info.name) *"
        } else {
            displayTitle = info.name
        }
        let subtitle = info.commitDate.map { relativeTimeString(from: $0) }
        // Show remote name as a dim suffix for remote branches
        let remoteSuffix = info.isRemote ? info.remoteName : nil

        return makeBranchCellView(
            icon: icon,
            title: displayTitle,
            subtitle: subtitle,
            remoteSuffix: remoteSuffix,
            inUse: suggestion.inUse,
            tableView: tableView
        )
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < suggestions.count {
            selectedIndex = row
            updatePathPreview()
        }
    }

    // MARK: - Cell Factory

    private func makeBranchCellView(
        icon: String,
        title: String,
        subtitle: String?,
        remoteSuffix: String?,
        inUse: Bool,
        tableView: NSTableView
    ) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("BranchCell")
        let cell: NSTableCellView

        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = makeBranchCell(identifier: cellID)
        }

        // Icon
        cell.imageView?.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = inUse ? .tertiaryLabelColor : .secondaryLabelColor

        // Title
        cell.textField?.stringValue = title
        cell.textField?.textColor = inUse ? .tertiaryLabelColor : .labelColor

        // Subtitle / time (tag 100)
        if let timeField = cell.viewWithTag(100) as? NSTextField {
            timeField.stringValue = subtitle ?? ""
            timeField.isHidden = subtitle == nil
        }

        // Remote suffix (tag 102)
        if let remoteField = cell.viewWithTag(102) as? NSTextField {
            remoteField.stringValue = remoteSuffix ?? ""
            remoteField.isHidden = remoteSuffix == nil
        }

        // "in use" badge (tag 101)
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

        let remoteField = NSTextField(labelWithString: "")
        remoteField.translatesAutoresizingMaskIntoConstraints = false
        remoteField.font = .systemFont(ofSize: Layout.badgeFontSize)
        remoteField.textColor = .quaternaryLabelColor
        remoteField.tag = 102
        cell.addSubview(remoteField)

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

            remoteField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: Layout.cellSpacing),
            remoteField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            timeField.leadingAnchor.constraint(greaterThanOrEqualTo: remoteField.trailingAnchor, constant: Layout.cellSpacing),
            timeField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            badgeField.leadingAnchor.constraint(greaterThanOrEqualTo: timeField.trailingAnchor, constant: Layout.cellSpacing),
            badgeField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Layout.cellTrailingPadding),
            badgeField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        remoteField.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        timeField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        badgeField.setContentCompressionResistancePriority(.required, for: .horizontal)

        return cell
    }

    // MARK: - Helpers

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let seconds = Int(interval)
        if seconds < 60 { return .localized("now") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: .localized("%dm ago"), minutes) }
        let hours = minutes / 60
        if hours < 24 { return String(format: .localized("%dh ago"), hours) }
        let days = hours / 24
        if days < 30 { return String(format: .localized("%dd ago"), days) }
        let months = days / 30
        if months < 12 { return String(format: .localized("%dmo ago"), months) }
        let years = days / 365
        return String(format: .localized("%dy ago"), years)
    }
}
