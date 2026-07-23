import AppKit
import MoriCore
import MoriGit
import MoriTerminal

// MARK: - Controller

/// NSWindowController managing a minimal floating worktree creation panel.
///
/// Layout: 2-row panel — branch name input on top, project/base-branch dropdowns + hint below.
@MainActor
final class WorktreeCreationController: NSWindowController {

    // MARK: - Constants

    private static let fallbackBranch = "main"
    private static let branchIconPrefix = "\u{2387} "

    // MARK: - Callbacks

    /// Called when the user confirms worktree creation.
    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?

    /// Called to fetch branches asynchronously.
    var fetchBranches: ((_ projectId: UUID, _ repoPath: String) async throws -> [GitBranchInfo])?

    /// Called to prefetch open GitHub issues + PRs for the `#` picker.
    /// Returns `[]` for remote/SSH projects (gh is local-only).
    var fetchGitHubItems: ((_ projectId: UUID, _ repoPath: String) async -> [GitHubWorkItem])?

    /// Called when the user switches projects in the popup.
    var onProjectChanged: ((UUID) -> Void)?

    // MARK: - State

    private var dataSource: WorktreeCreationDataSource?
    private var projects: [Project] = []
    private var selectedProjectId: UUID?
    private var repoPath: String = ""
    private var fetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // GitHub `#` picker state.
    private var githubItems: [GitHubWorkItem] = []
    private var filteredItems: [GitHubWorkItem] = []
    private var githubFetchGeneration: Int = 0
    private var githubModeActive: Bool = false
    private var selectedSuggestionIndex: Int = -1

    // MARK: - Views

    private let branchNameField = NSTextField()
    private let toolbarContainer = NSView()
    private let projectPopup = NSPopUpButton()
    private let baseBranchPopup = NSPopUpButton()
    private let createHintLabel = NSTextField(labelWithString: "")
    private let containerView = NSView()

    // Suggestions list (GitHub `#` picker).
    private let suggestionsScrollView = NSScrollView()
    private let suggestionsTable = NSTableView()
    private var suggestionsTopConstraint: NSLayoutConstraint!
    private var suggestionsHeightConstraint: NSLayoutConstraint!

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 480
        static let panelPaddingH: CGFloat = 12
        static let cornerRadius: CGFloat = 10

        static let branchNameTopPadding: CGFloat = 12
        static let branchNameHeight: CGFloat = 28
        static let toolbarTopGap: CGFloat = 8
        static let toolbarHeight: CGFloat = 24
        static let bottomPadding: CGFloat = 10

        // 12 + 28 + 8 + 24 + 10 = 82
        static let panelHeight: CGFloat = 82

        static let panelTopOffset: CGFloat = 80

        // Suggestions list.
        static let suggestionsTopGap: CGFloat = 6
        static let suggestionRowHeight: CGFloat = 26
        static let maxVisibleSuggestions = 8
        static let suggestionsBottomPadding: CGFloat = 8
    }

    // MARK: - Init

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight),
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
        panel.becomesKeyOnlyIfNeeded = false

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
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String,
        themeInfo: GhosttyThemeInfo
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath

        branchNameField.stringValue = ""
        dataSource = nil
        exitGitHubMode()

        applyTheme(themeInfo)
        populateProjectPopup()
        resetBaseBranchPopup()

        positionPanel()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(branchNameField)

        fetchBranchesAsync(repoPath: repoPath)
        fetchGitHubItemsAsync(repoPath: repoPath)
    }

    /// Lightweight refresh when the user switches projects — re-fetches branches
    /// without re-positioning or re-theming the panel.
    func refresh(
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath

        branchNameField.stringValue = ""
        dataSource = nil
        exitGitHubMode()

        populateProjectPopup()
        resetBaseBranchPopup()

        fetchBranchesAsync(repoPath: repoPath)
        fetchGitHubItemsAsync(repoPath: repoPath)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    // MARK: - Theme

    private func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        guard let panel = window as? NSPanel else { return }
        panel.backgroundColor = themeInfo.background
        panel.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        containerView.layer?.backgroundColor = themeInfo.background.cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        guard let panel = window else { return }

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Layout.cornerRadius
        panel.contentView?.layer?.masksToBounds = true

        containerView.wantsLayer = true
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

        setupBranchNameField()
        setupToolbarRow()
        setupSuggestionsList()
        layoutViews()
    }

    private func setupSuggestionsList() {
        suggestionsTable.translatesAutoresizingMaskIntoConstraints = false
        suggestionsTable.headerView = nil
        suggestionsTable.backgroundColor = .clear
        suggestionsTable.rowHeight = Layout.suggestionRowHeight
        suggestionsTable.intercellSpacing = NSSize(width: 0, height: 0)
        suggestionsTable.selectionHighlightStyle = .regular
        suggestionsTable.allowsEmptySelection = true
        suggestionsTable.allowsMultipleSelection = false
        suggestionsTable.gridStyleMask = []
        suggestionsTable.dataSource = self
        suggestionsTable.delegate = self
        suggestionsTable.target = self
        suggestionsTable.action = #selector(suggestionRowClicked(_:))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion"))
        column.resizingMask = .autoresizingMask
        suggestionsTable.addTableColumn(column)

        suggestionsScrollView.translatesAutoresizingMaskIntoConstraints = false
        suggestionsScrollView.documentView = suggestionsTable
        suggestionsScrollView.hasVerticalScroller = true
        suggestionsScrollView.drawsBackground = false
        suggestionsScrollView.borderType = .noBorder
        suggestionsScrollView.automaticallyAdjustsContentInsets = false
        suggestionsScrollView.isHidden = true
        containerView.addSubview(suggestionsScrollView)
    }

    private func setupKeyEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.window, panel.isVisible else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+Enter from anywhere: confirm creation
            if event.keyCode == 36, mods.contains(.command) {
                self.confirmInput()
                return nil
            }

            // Esc from anywhere: dismiss
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }

            return event
        }
    }

    // MARK: - Branch Name Field

    private func setupBranchNameField() {
        branchNameField.translatesAutoresizingMaskIntoConstraints = false
        branchNameField.placeholderString = .localized("Branch name")
        branchNameField.font = .systemFont(ofSize: 14, weight: .regular)
        branchNameField.isBordered = true
        branchNameField.bezelStyle = .roundedBezel
        branchNameField.focusRingType = .none
        branchNameField.delegate = self
        branchNameField.target = self
        branchNameField.action = #selector(branchNameAction(_:))
        containerView.addSubview(branchNameField)
    }

    // MARK: - Toolbar Row

    private func setupToolbarRow() {
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(toolbarContainer)

        // Project popup
        projectPopup.translatesAutoresizingMaskIntoConstraints = false
        projectPopup.controlSize = .small
        projectPopup.font = .systemFont(ofSize: 12)
        projectPopup.isBordered = false
        projectPopup.target = self
        projectPopup.action = #selector(projectChanged(_:))
        toolbarContainer.addSubview(projectPopup)

        // Base branch popup
        baseBranchPopup.translatesAutoresizingMaskIntoConstraints = false
        baseBranchPopup.controlSize = .small
        baseBranchPopup.font = .systemFont(ofSize: 12)
        baseBranchPopup.isBordered = false
        // No target/action — selection is read at confirm time
        toolbarContainer.addSubview(baseBranchPopup)

        // Create hint label
        createHintLabel.translatesAutoresizingMaskIntoConstraints = false
        createHintLabel.stringValue = "\u{2318}\u{23CE} " + .localized("to create")
        createHintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        createHintLabel.textColor = .tertiaryLabelColor
        createHintLabel.isEditable = false
        createHintLabel.isBordered = false
        createHintLabel.backgroundColor = .clear
        toolbarContainer.addSubview(createHintLabel)

        NSLayoutConstraint.activate([
            projectPopup.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: Layout.panelPaddingH),
            projectPopup.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            baseBranchPopup.leadingAnchor.constraint(equalTo: projectPopup.trailingAnchor, constant: 8),
            baseBranchPopup.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            createHintLabel.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -Layout.panelPaddingH),
            createHintLabel.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
        ])
    }

    // MARK: - Layout

    private func layoutViews() {
        // The toolbar is NOT pinned to the container bottom: the panel frame has a
        // fixed height, so pinning would fight the downward growth of the
        // suggestions list. Vertical positions flow from the top instead.
        suggestionsTopConstraint = suggestionsScrollView.topAnchor.constraint(
            equalTo: toolbarContainer.bottomAnchor, constant: 0
        )
        suggestionsHeightConstraint = suggestionsScrollView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Branch name field
            branchNameField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.branchNameTopPadding),
            branchNameField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelPaddingH),
            branchNameField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelPaddingH),
            branchNameField.heightAnchor.constraint(equalToConstant: Layout.branchNameHeight),

            // Toolbar container
            toolbarContainer.topAnchor.constraint(equalTo: branchNameField.bottomAnchor, constant: Layout.toolbarTopGap),
            toolbarContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: Layout.toolbarHeight),

            // Suggestions list (below the toolbar; height/gap toggled at runtime)
            suggestionsTopConstraint,
            suggestionsScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelPaddingH),
            suggestionsScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelPaddingH),
            suggestionsHeightConstraint,
        ])
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel = window else { return }

        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.midX - Layout.panelWidth / 2
            let y = mainFrame.maxY - Layout.panelHeight - Layout.panelTopOffset
            panel.setFrame(NSRect(x: x, y: y, width: Layout.panelWidth, height: Layout.panelHeight), display: true)
        } else {
            panel.setFrame(NSRect(x: 0, y: 0, width: Layout.panelWidth, height: Layout.panelHeight), display: true)
            panel.center()
        }
    }

    // MARK: - Branch Fetching

    private func resetBaseBranchPopup() {
        baseBranchPopup.removeAllItems()
        baseBranchPopup.addItem(withTitle: Self.branchIconPrefix + Self.fallbackBranch)
        baseBranchPopup.lastItem?.representedObject = Self.fallbackBranch
        baseBranchPopup.isEnabled = true
    }

    private func fetchBranchesAsync(repoPath: String) {
        fetchGeneration += 1
        let currentGeneration = fetchGeneration
        Task { [weak self] in
            guard let self else { return }
            let branches: [GitBranchInfo]
            do {
                if let projectId = self.selectedProjectId {
                    branches = try await self.fetchBranches?(projectId, repoPath) ?? []
                } else {
                    branches = []
                }
            } catch {
                branches = []
            }
            guard self.fetchGeneration == currentGeneration else { return }
            self.dataSource = WorktreeCreationDataSource(branches: branches)
            self.populateBaseBranchPopup()
        }
    }

    /// Prefetch issues + PRs for the `#` picker. Uses the same generation-counter
    /// staleness guard as branch fetching so a slow response from a previously
    /// selected project can't clobber the current one.
    private func fetchGitHubItemsAsync(repoPath: String) {
        githubItems = []
        githubFetchGeneration += 1
        let currentGeneration = githubFetchGeneration
        Task { [weak self] in
            guard let self, let projectId = self.selectedProjectId else { return }
            let items = await self.fetchGitHubItems?(projectId, repoPath) ?? []
            guard self.githubFetchGeneration == currentGeneration else { return }
            self.githubItems = items
            // If the user already typed `#` before the fetch landed, re-filter.
            if self.githubModeActive {
                self.filterSuggestions(query: self.currentGitHubQuery())
            }
        }
    }

    // MARK: - Populate Popups

    private func populateProjectPopup() {
        projectPopup.removeAllItems()
        for project in projects {
            projectPopup.addItem(withTitle: project.name)
        }
        if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
            projectPopup.selectItem(at: idx)
        }
    }

    private func populateBaseBranchPopup() {
        guard let ds = dataSource else { return }
        baseBranchPopup.removeAllItems()
        let branchNames = ds.localBranchNames
        if branchNames.isEmpty {
            baseBranchPopup.addItem(withTitle: Self.branchIconPrefix + Self.fallbackBranch)
            baseBranchPopup.lastItem?.representedObject = Self.fallbackBranch
        } else {
            for name in branchNames {
                baseBranchPopup.addItem(withTitle: Self.branchIconPrefix + name)
                baseBranchPopup.lastItem?.representedObject = name
            }
            if let idx = branchNames.firstIndex(of: ds.defaultBaseBranch) {
                baseBranchPopup.selectItem(at: idx)
            }
        }
    }

    // MARK: - Confirm

    private func confirmInput() {
        // In `#` picker mode, Enter/Cmd+Enter confirms the highlighted
        // suggestion (if any) rather than creating a literal `#…` branch.
        if githubModeActive {
            if let item = currentSelectedItem() {
                confirmSuggestion(item)
            }
            return
        }

        let branchText = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branchText.isEmpty else { return }

        // Check if typed text exactly matches an existing branch
        if let match = dataSource?.exactMatch(for: branchText) {
            dismiss()
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: match.name,
                isNewBranch: false,
                baseBranch: nil
            ))
            return
        }

        // New branch — use base branch from popup
        let baseBranch = selectedBaseBranch()
        dismiss()
        onCreateWorktree?(WorktreeCreationRequest(
            branchName: branchText,
            isNewBranch: true,
            baseBranch: baseBranch
        ))
    }

    private func selectedBaseBranch() -> String {
        if let name = baseBranchPopup.selectedItem?.representedObject as? String, !name.isEmpty {
            return name
        }
        return dataSource?.defaultBaseBranch ?? Self.fallbackBranch
    }

    // MARK: - GitHub Picker

    /// The text after the leading `#`, used to filter suggestions.
    private func currentGitHubQuery() -> String {
        let text = branchNameField.stringValue
        guard text.hasPrefix("#") else { return "" }
        return String(text.dropFirst())
    }

    private func currentSelectedItem() -> GitHubWorkItem? {
        guard selectedSuggestionIndex >= 0, selectedSuggestionIndex < filteredItems.count else {
            return nil
        }
        return filteredItems[selectedSuggestionIndex]
    }

    /// React to text changes: recognize a pasted GitHub URL, enter/leave `#`
    /// picker mode, and filter suggestions.
    private func handleTextChange() {
        let text = branchNameField.stringValue

        if let (kind, number) = GitHubWorkItem.parseURL(text) {
            handleURLSelection(kind: kind, number: number)
            return
        }

        if text.hasPrefix("#") {
            githubModeActive = true
            filterSuggestions(query: currentGitHubQuery())
        } else {
            exitGitHubMode()
        }
    }

    private func filterSuggestions(query: String) {
        let q = query.lowercased()
        filteredItems = githubItems.filter { item in
            if q.isEmpty { return true }
            return "\(item.number)".hasPrefix(q) || item.title.lowercased().contains(q)
        }
        selectedSuggestionIndex = filteredItems.isEmpty ? -1 : 0
        suggestionsTable.reloadData()
        applySuggestionSelection()
        updateSuggestionsLayout()
    }

    private func exitGitHubMode() {
        githubModeActive = false
        filteredItems = []
        selectedSuggestionIndex = -1
        suggestionsTable.reloadData()
        updateSuggestionsLayout()
    }

    /// Grow/collapse the panel to fit the visible suggestion rows, keeping the
    /// panel's top edge fixed (AppKit frames are bottom-left origin).
    private func updateSuggestionsLayout() {
        let rowCount = filteredItems.count
        let visible = min(rowCount, Layout.maxVisibleSuggestions)
        let listHeight = githubModeActive && rowCount > 0
            ? CGFloat(visible) * Layout.suggestionRowHeight
            : 0

        suggestionsScrollView.isHidden = (listHeight == 0)
        suggestionsHeightConstraint.constant = listHeight
        suggestionsTopConstraint.constant = listHeight > 0 ? Layout.suggestionsTopGap : 0

        let extra = listHeight > 0
            ? Layout.suggestionsTopGap + listHeight + Layout.suggestionsBottomPadding
            : 0
        setPanelHeight(Layout.panelHeight + extra)
    }

    /// Resize the panel to `height` while pinning its top edge (max Y).
    private func setPanelHeight(_ height: CGFloat) {
        guard let panel = window else { return }
        let frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.maxY - height,
            width: frame.width,
            height: height
        )
        panel.setFrame(newFrame, display: true)
    }

    private func applySuggestionSelection() {
        guard selectedSuggestionIndex >= 0, selectedSuggestionIndex < filteredItems.count else {
            suggestionsTable.deselectAll(nil)
            return
        }
        suggestionsTable.selectRowIndexes(
            IndexSet(integer: selectedSuggestionIndex),
            byExtendingSelection: false
        )
        suggestionsTable.scrollRowToVisible(selectedSuggestionIndex)
    }

    private func moveSuggestionSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let count = filteredItems.count
        var next = (selectedSuggestionIndex < 0 ? 0 : selectedSuggestionIndex) + delta
        next = max(0, min(count - 1, next))
        selectedSuggestionIndex = next
        applySuggestionSelection()
    }

    /// Confirm a picked issue/PR — creates immediately (no second confirm).
    private func confirmSuggestion(_ item: GitHubWorkItem) {
        dismiss()
        switch item.kind {
        case .issue:
            let branch = GitHubWorkItem.issueBranchName(number: item.number, title: item.title)
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: branch,
                isNewBranch: true,
                baseBranch: selectedBaseBranch(),
                origin: .issue(number: item.number)
            ))
        case .pullRequest:
            let headRef = item.headRefName ?? ""
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: headRef.isEmpty ? "pr-\(item.number)" : headRef,
                isNewBranch: false,
                baseBranch: nil,
                origin: .pullRequest(number: item.number, headRef: headRef)
            ))
        }
    }

    /// Handle a pasted GitHub URL. Match the prefetched list first; otherwise an
    /// issue falls back to `issue-<n>` and a PR is resolved downstream via
    /// `gh pr view` (empty headRef signals the manager to resolve it).
    private func handleURLSelection(kind: GitHubWorkItem.Kind, number: Int) {
        if let item = githubItems.first(where: { $0.kind == kind && $0.number == number }) {
            confirmSuggestion(item)
            return
        }
        dismiss()
        switch kind {
        case .issue:
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: GitHubWorkItem.issueBranchName(number: number, title: ""),
                isNewBranch: true,
                baseBranch: selectedBaseBranch(),
                origin: .issue(number: number)
            ))
        case .pullRequest:
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: "pr-\(number)",
                isNewBranch: false,
                baseBranch: nil,
                origin: .pullRequest(number: number, headRef: "")
            ))
        }
    }

    @objc private func suggestionRowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < filteredItems.count else { return }
        confirmSuggestion(filteredItems[row])
    }

    // MARK: - Actions

    @objc private func branchNameAction(_ sender: NSTextField) {
        confirmInput()
    }

    @objc private func projectChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < projects.count else { return }
        let newProject = projects[idx]
        guard newProject.id != selectedProjectId else { return }
        selectedProjectId = newProject.id
        onProjectChanged?(newProject.id)
    }

}

// MARK: - NSTextFieldDelegate

extension WorktreeCreationController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as AnyObject) === branchNameField else { return }
        handleTextChange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === branchNameField else { return false }

        // Arrow keys drive the suggestion selection while in `#` picker mode.
        if githubModeActive {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                moveSuggestionSelection(by: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                moveSuggestionSelection(by: 1)
                return true
            }
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmInput()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            window?.makeFirstResponder(projectPopup)
            return true
        }
        return false
    }
}

// MARK: - Suggestions Table

extension WorktreeCreationController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        return makeSuggestionCell(for: filteredItems[row])
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }

    /// Keep the model's selection index in sync with mouse-driven selection.
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = suggestionsTable.selectedRow
        if row >= 0, row < filteredItems.count {
            selectedSuggestionIndex = row
        }
    }

    private func makeSuggestionCell(for item: GitHubWorkItem) -> NSView {
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let symbol = item.kind == .issue ? "smallcircle.filled.circle" : "arrow.triangle.pull"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown

        let numberLabel = NSTextField(labelWithString: "#\(item.number)")
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        numberLabel.textColor = .secondaryLabelColor
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)
        numberLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, numberLabel, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        if item.kind == .pullRequest, item.isDraft {
            let draftLabel = NSTextField(labelWithString: .localized("Draft"))
            draftLabel.font = .systemFont(ofSize: 11)
            draftLabel.textColor = .tertiaryLabelColor
            draftLabel.setContentHuggingPriority(.required, for: .horizontal)
            draftLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(draftLabel)
        }

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
