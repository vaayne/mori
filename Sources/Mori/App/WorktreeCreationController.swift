import AppKit
import MoriCore
import MoriGit

// MARK: - Row Model

/// Represents a single row in the branch list — either a section header or a branch.
enum PanelRow {
    case sectionHeader(String)
    case branch(BranchSuggestion)
}

// MARK: - Controller

/// NSWindowController managing a floating worktree creation panel.
///
/// Design: The search field is the primary input. As you type, autocomplete suggestions
/// filter below. Enter creates from the typed name -- if it matches an existing branch,
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
    private var rows: [PanelRow] = []
    private var suggestions: [BranchSuggestion] = []
    private var selectedIndex: Int = -1 // Index into `rows` (only branch rows selectable)
    private var projectName: String = ""
    private var projectId: UUID?
    private var repoPath: String = ""
    /// Incremented on each show() to invalidate stale async branch fetches.
    private var fetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // MARK: - Views

    private let searchField = NSTextField()
    private let hintLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let tableSeparator = NSBox()

    // Search field background
    private let searchFieldBackground = NSView()

    // Footer views
    private let footerContainer = NSView()
    private let footerSeparator = NSBox()
    private let baseLabel = NSTextField(labelWithString: "")
    private let baseBranchField = NSTextField()
    private let templatePopup = NSPopUpButton()
    private let pathLabel = NSTextField(labelWithString: "")

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 560
        static let panelPaddingH: CGFloat = 12
        static let panelTopPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 10

        static let searchFieldHeight: CGFloat = 36
        static let searchFieldCornerRadius: CGFloat = 8
        static let searchFontSize: CGFloat = 14

        static let hintHeight: CGFloat = 16
        static let hintGap: CGFloat = 4

        static let listGap: CGFloat = 6
        static let sectionHeaderHeight: CGFloat = 20
        static let sectionHeaderLeading: CGFloat = 12

        static let rowHeight: CGFloat = 30
        static let rowPaddingH: CGFloat = 12
        static let cellIconSize: CGFloat = 13
        static let cellIconGap: CGFloat = 8
        static let branchFontSize: CGFloat = 13
        static let commitAgeLaneWidth: CGFloat = 60
        static let commitAgeFontSize: CGFloat = 11

        static let maxVisibleRows: Int = 10
        static let panelTopOffset: CGFloat = 80

        static let footerHeight: CGFloat = 36
    }

    // MARK: - Init

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: 300),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
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

        // Hide traffic light buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

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
        rows = []
        dataSource = nil
        baseBranchField.stringValue = ""
        templatePopup.selectItem(at: 0)
        tableView.reloadData()
        updateFooter()

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

        // Panel corner radius
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Layout.cornerRadius
        panel.contentView?.layer?.masksToBounds = true

        containerView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(containerView)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
                containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

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

            // Handle Enter from template popup -- confirm
            if event.keyCode == 36, firstResponder === self.templatePopup {
                self.confirmInput()
                return nil
            }

            // Handle Esc from template popup -- back to search
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
        searchField.font = .monospacedSystemFont(ofSize: Layout.searchFontSize, weight: .medium)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))

        // Placeholder font styling
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: Layout.searchFontSize, weight: .regular),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        searchField.placeholderAttributedString = NSAttributedString(
            string: .localized("Branch name..."),
            attributes: placeholderAttrs
        )

        // Search field background
        searchFieldBackground.translatesAutoresizingMaskIntoConstraints = false
        searchFieldBackground.wantsLayer = true
        searchFieldBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        searchFieldBackground.layer?.cornerRadius = Layout.searchFieldCornerRadius
        containerView.addSubview(searchFieldBackground)
        containerView.addSubview(searchField)

        // Hint label below search field
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.stringValue = "\u{23CE} to create \u{00B7} \u{2191}\u{2193} to select"
        hintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.backgroundColor = .clear
        containerView.addSubview(hintLabel)
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branches"))
        column.title = ""
        column.width = Layout.panelWidth - Layout.panelPaddingH * 2
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.rowHeight
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.backgroundColor = .windowBackgroundColor
        tableView.gridStyleMask = []

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        containerView.addSubview(scrollView)
    }

    private func setupFooter() {
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(footerContainer)

        // Top divider
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .custom
        footerSeparator.fillColor = .separatorColor
        footerContainer.addSubview(footerSeparator)

        // "Base:" label
        baseLabel.translatesAutoresizingMaskIntoConstraints = false
        baseLabel.stringValue = "Base:"
        baseLabel.font = .systemFont(ofSize: 11, weight: .regular)
        baseLabel.textColor = .tertiaryLabelColor
        baseLabel.isEditable = false
        baseLabel.isBordered = false
        baseLabel.backgroundColor = .clear
        footerContainer.addSubview(baseLabel)

        // Base branch editable field
        baseBranchField.translatesAutoresizingMaskIntoConstraints = false
        baseBranchField.placeholderString = "main"
        baseBranchField.font = .systemFont(ofSize: 11, weight: .regular)
        baseBranchField.textColor = .labelColor
        baseBranchField.isBordered = false
        baseBranchField.bezelStyle = .roundedBezel
        baseBranchField.isBezeled = false
        baseBranchField.drawsBackground = false
        baseBranchField.focusRingType = .none
        baseBranchField.delegate = self
        footerContainer.addSubview(baseBranchField)

        // Template popup
        templatePopup.translatesAutoresizingMaskIntoConstraints = false
        templatePopup.font = .systemFont(ofSize: 11)
        templatePopup.removeAllItems()
        for template in TemplateRegistry.all {
            templatePopup.addItem(withTitle: "Template: \(template.name.capitalized)")
        }
        templatePopup.controlSize = .small
        templatePopup.isBordered = false
        templatePopup.target = self
        templatePopup.action = #selector(templateChanged(_:))
        footerContainer.addSubview(templatePopup)

        // Path preview
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.isEditable = false
        pathLabel.isBordered = false
        pathLabel.backgroundColor = .clear
        pathLabel.lineBreakMode = .byTruncatingMiddle
        footerContainer.addSubview(pathLabel)

        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),

            baseLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.panelPaddingH),
            baseLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),

            baseBranchField.leadingAnchor.constraint(equalTo: baseLabel.trailingAnchor, constant: 4),
            baseBranchField.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
            baseBranchField.widthAnchor.constraint(equalToConstant: 80),

            templatePopup.leadingAnchor.constraint(equalTo: baseBranchField.trailingAnchor, constant: 12),
            templatePopup.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),

            pathLabel.leadingAnchor.constraint(greaterThanOrEqualTo: templatePopup.trailingAnchor, constant: 12),
            pathLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -Layout.panelPaddingH),
            pathLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),

            footerContainer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
        ])

        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func layoutViews() {
        tableSeparator.translatesAutoresizingMaskIntoConstraints = false
        tableSeparator.boxType = .custom
        tableSeparator.fillColor = .separatorColor
        containerView.addSubview(tableSeparator)

        let searchBg = searchFieldBackground

        NSLayoutConstraint.activate([
            // Search field background
            searchBg.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.panelTopPadding),
            searchBg.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelPaddingH),
            searchBg.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelPaddingH),
            searchBg.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),

            // Search field (inside background)
            searchField.leadingAnchor.constraint(equalTo: searchBg.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchBg.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchBg.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight - 4),

            // Hint label
            hintLabel.topAnchor.constraint(equalTo: searchBg.bottomAnchor, constant: Layout.hintGap),
            hintLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelPaddingH + 10),
            hintLabel.heightAnchor.constraint(equalToConstant: Layout.hintHeight),

            // Separator
            tableSeparator.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: Layout.listGap),
            tableSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableSeparator.heightAnchor.constraint(equalToConstant: 1),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: tableSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Footer
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
        let topArea = Layout.panelTopPadding + Layout.searchFieldHeight
            + Layout.hintGap + Layout.hintHeight + Layout.listGap + 1 // separator
        let rowCount = rows.isEmpty ? 1 : min(rows.count, Layout.maxVisibleRows)
        let tableHeight = CGFloat(rowCount) * Layout.rowHeight
        return topArea + tableHeight + Layout.footerHeight
    }

    // MARK: - Results

    private func updateResults() {
        let query = searchField.stringValue
        let grouped = dataSource?.filteredGrouped(query: query)
            ?? (local: [], remote: [])

        // Build flat rows — only show REMOTE header when remote branches present
        var newRows: [PanelRow] = []

        for s in grouped.local {
            newRows.append(.branch(s))
        }
        if !grouped.remote.isEmpty {
            newRows.append(.sectionHeader("REMOTE"))
            for s in grouped.remote {
                newRows.append(.branch(s))
            }
        }

        rows = newRows
        suggestions = grouped.local + grouped.remote

        // Select first branch row
        selectedIndex = rows.firstIndex(where: { if case .branch = $0 { return true }; return false }) ?? -1

        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        updateFooter()
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
        if selectedIndex >= 0, selectedIndex < rows.count,
           case .branch(let suggestion) = rows[selectedIndex] {
            let info = suggestion.info
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

        // No match -- create new branch
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
        guard selectedIndex >= 0, selectedIndex < rows.count,
              case .branch(let suggestion) = rows[selectedIndex] else {
            confirmInput()
            return
        }

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
        guard !rows.isEmpty else { return }
        var candidate = selectedIndex - 1
        while candidate >= 0 {
            if case .branch = rows[candidate] { break }
            candidate -= 1
        }
        guard candidate >= 0 else { return }
        selectedIndex = candidate
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        updateFooter()
    }

    private func moveSelectionDown() {
        guard !rows.isEmpty else { return }
        var candidate = selectedIndex + 1
        while candidate < rows.count {
            if case .branch = rows[candidate] { break }
            candidate += 1
        }
        guard candidate < rows.count else { return }
        selectedIndex = candidate
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        updateFooter()
    }

    // MARK: - Footer

    private func updateFooter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let isExisting = query.isEmpty ? false : dataSource?.exactMatch(for: query) != nil

        // Base label + field: hide when selecting an existing branch
        baseLabel.isHidden = isExisting
        baseBranchField.isHidden = isExisting

        // Path preview
        if query.isEmpty {
            pathLabel.stringValue = ""
        } else {
            let branchForPath: String
            if let match = dataSource?.exactMatch(for: query) {
                branchForPath = match.isRemote ? match.displayName : match.name
            } else {
                branchForPath = query
            }
            pathLabel.stringValue = WorktreeCreationDataSource.previewPath(
                projectName: projectName,
                branchName: branchForPath
            )
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
        confirmInput()
    }

    @objc private func templateChanged(_ sender: NSPopUpButton) {
        updateFooter()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .branch = rows[row] else { return }
        selectedIndex = row
        confirmSuggestion()
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

    /// Returns the BranchSuggestion for a given row index, or nil if header.
    private func branchSuggestion(at row: Int) -> BranchSuggestion? {
        guard row >= 0, row < rows.count else { return nil }
        if case .branch(let s) = rows[row] { return s }
        return nil
    }
}

// MARK: - NSTextFieldDelegate

extension WorktreeCreationController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === searchField {
            updateResults()
        } else if field === baseBranchField {
            updateFooter()
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
        rows.count
    }
}

// MARK: - NSTableViewDelegate

extension WorktreeCreationController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .sectionHeader:
            return Layout.sectionHeaderHeight
        case .branch:
            return Layout.rowHeight
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .sectionHeader = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .sectionHeader = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }

        switch rows[row] {
        case .sectionHeader(let title):
            return makeSectionHeaderView(title: title)
        case .branch(let suggestion):
            return makeBranchRowView(suggestion: suggestion)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < rows.count, case .branch = rows[row] {
            selectedIndex = row
            updateFooter()
        }
    }

    // MARK: - Section Header

    private func makeSectionHeaderView(title: String) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.sectionHeaderLeading),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    // MARK: - Branch Row

    private func makeBranchRowView(suggestion: BranchSuggestion) -> NSView {
        let info = suggestion.info
        let cell = NSTableCellView()

        // Icon — always "arrow.triangle.branch"
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        cell.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Layout.rowPaddingH),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),
        ])

        // Branch name
        let displayName = info.isRemote ? info.displayName : info.name
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: Layout.branchFontSize, weight: .regular)
        nameLabel.textColor = info.isRemote ? .secondaryLabelColor : .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        cell.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Layout.cellIconGap),
            nameLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Trailing items laid out right-to-left
        var trailingRef = cell.trailingAnchor
        var trailingConst: CGFloat = -Layout.rowPaddingH

        // Commit age (right-aligned)
        if let commitDate = info.commitDate {
            let timeLabel = NSTextField(labelWithString: relativeTimeString(from: commitDate))
            timeLabel.translatesAutoresizingMaskIntoConstraints = false
            timeLabel.font = .systemFont(ofSize: Layout.commitAgeFontSize, weight: .regular)
            timeLabel.textColor = .tertiaryLabelColor
            timeLabel.alignment = .right
            cell.addSubview(timeLabel)
            NSLayoutConstraint.activate([
                timeLabel.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingConst),
                timeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                timeLabel.widthAnchor.constraint(equalToConstant: Layout.commitAgeLaneWidth),
            ])
            trailingRef = timeLabel.leadingAnchor
            trailingConst = -6
        }

        // In-use checkmark
        if suggestion.inUse {
            let checkLabel = NSTextField(labelWithString: "\u{2713}")
            checkLabel.translatesAutoresizingMaskIntoConstraints = false
            checkLabel.font = .systemFont(ofSize: 12, weight: .medium)
            checkLabel.textColor = .tertiaryLabelColor
            checkLabel.isEditable = false
            checkLabel.isBordered = false
            checkLabel.backgroundColor = .clear
            cell.addSubview(checkLabel)
            NSLayoutConstraint.activate([
                checkLabel.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingConst),
                checkLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            trailingRef = checkLabel.leadingAnchor
            trailingConst = -6
        }

        // HEAD "default" badge
        if info.isHead {
            let badge = NSTextField(labelWithString: "default")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = .systemFont(ofSize: 10, weight: .regular)
            badge.textColor = .tertiaryLabelColor
            badge.isEditable = false
            badge.isBordered = false
            badge.backgroundColor = .clear

            let badgeContainer = NSView()
            badgeContainer.translatesAutoresizingMaskIntoConstraints = false
            badgeContainer.wantsLayer = true
            badgeContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            badgeContainer.layer?.borderColor = NSColor.separatorColor.cgColor
            badgeContainer.layer?.borderWidth = 1
            badgeContainer.layer?.cornerRadius = 4
            badgeContainer.addSubview(badge)

            cell.addSubview(badgeContainer)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
                badge.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
                badge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

                badgeContainer.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
                badgeContainer.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                badgeContainer.heightAnchor.constraint(equalToConstant: 18),
            ])
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingRef, constant: trailingConst - 60).isActive = true
        } else {
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingRef, constant: trailingConst).isActive = true
        }

        return cell
    }
}
