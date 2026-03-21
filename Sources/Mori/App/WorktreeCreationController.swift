import AppKit
import MoriCore
import MoriGit

// MARK: - Row Model

/// Represents a single row in the branch list — either a section header or a branch.
enum PanelRow {
    case sectionHeader(String)
    case branch(BranchSuggestion)
}

// MARK: - Filter Tab

/// Filter mode for the branch list.
private enum FilterTab: Int {
    case all = 0
    case worktrees = 1
}

// MARK: - Controller

/// NSWindowController managing a floating worktree creation panel.
///
/// Design: GitButler-inspired layout with branch name input at top, project/base branch
/// dropdowns, filter tabs, search field, and a scrollable branch list. The branch name
/// field is the primary input for creating new branches; the list below is for reference
/// and selecting existing branches.
@MainActor
final class WorktreeCreationController: NSWindowController {

    // MARK: - Callbacks

    /// Called when the user confirms worktree creation.
    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?

    /// Called to fetch branches asynchronously.
    var fetchBranches: ((_ repoPath: String) async throws -> [GitBranchInfo])?

    /// Called when the user switches projects in the popup.
    var onProjectChanged: ((UUID) -> Void)?

    // MARK: - State

    private var dataSource: WorktreeCreationDataSource?
    private var rows: [PanelRow] = []
    private var selectedIndex: Int = -1
    private var projects: [Project] = []
    private var selectedProjectId: UUID?
    private var repoPath: String = ""
    private var isExistingBranch: Bool = false
    private var activeFilterTab: FilterTab = .all
    private var fetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // MARK: - Views

    // Branch name input (top)
    private let branchNameField = NSTextField()

    // Toolbar row
    private let toolbarContainer = NSView()
    private let projectPopup = NSPopUpButton()
    private let baseBranchPopup = NSPopUpButton()
    private let createHintLabel = NSTextField(labelWithString: "")
    private let toolbarSeparator = NSBox()

    // Filter tabs
    private let filterTabsContainer = NSView()
    private let filterSegment = NSSegmentedControl()
    private let filterSeparator = NSBox()

    // Search field
    private let searchFieldContainer = NSView()
    private let searchField = NSSearchField()
    private let searchSeparator = NSBox()

    // Branch list
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    // Path preview footer
    private let footerContainer = NSView()
    private let footerSeparator = NSBox()
    private let pathLabel = NSTextField(labelWithString: "")

    // Container
    private let containerView = NSView()

    // MARK: - Scroll height constraint

    private var scrollHeightConstraint: NSLayoutConstraint?

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 520
        static let panelPaddingH: CGFloat = 12
        static let cornerRadius: CGFloat = 10

        // Branch name area: 10 + 28 + 8 = 46
        static let branchNameTopPadding: CGFloat = 10
        static let branchNameHeight: CGFloat = 28
        static let branchNameBottomGap: CGFloat = 8

        // Toolbar row: 30 + 1 = 31
        static let toolbarHeight: CGFloat = 30
        static let toolbarSepHeight: CGFloat = 1

        // Filter tabs: 28 + 1 = 29
        static let filterTabsHeight: CGFloat = 28
        static let filterSepHeight: CGFloat = 1

        // Search field: 6 + 24 + 6 + 1 = 37
        static let searchPaddingV: CGFloat = 6
        static let searchFieldHeight: CGFloat = 24
        static let searchSepHeight: CGFloat = 1

        // Branch list
        static let rowHeight: CGFloat = 28
        static let sectionHeaderHeight: CGFloat = 20
        static let maxVisibleRows: Int = 8

        // Path footer: 24
        static let footerHeight: CGFloat = 24

        // Row internals
        static let rowPaddingH: CGFloat = 12
        static let cellIconSize: CGFloat = 12
        static let cellIconGap: CGFloat = 6
        static let branchFontSize: CGFloat = 13
        static let commitAgeFontSize: CGFloat = 11
        static let commitAgeLaneWidth: CGFloat = 50

        // Section header
        static let sectionHeaderLeading: CGFloat = 12

        // Panel positioning
        static let panelTopOffset: CGFloat = 80

        // Fixed overhead: 46 + 31 + 29 + 37 + 24 = 167
        static let fixedOverhead: CGFloat = 167
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
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String,
        existingBranches: Set<String>
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath

        // Reset state
        branchNameField.stringValue = ""
        searchField.stringValue = ""
        selectedIndex = -1
        isExistingBranch = false
        activeFilterTab = .all
        rows = []
        dataSource = nil
        tableView.reloadData()

        // Populate project popup
        populateProjectPopup()

        // Reset filter segment
        filterSegment.selectSegment(withTag: FilterTab.all.rawValue)

        // Reset base branch popup
        baseBranchPopup.removeAllItems()
        baseBranchPopup.addItem(withTitle: "\u{2387} main")
        baseBranchPopup.isEnabled = true

        updatePathPreview()
        updateFilterCounts()

        // Position and show
        positionPanel()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(branchNameField)

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
                self.populateBaseBranchPopup()
                self.updateFilterCounts()
                self.updateResults()
            } catch {
                guard self.fetchGeneration == currentGeneration else { return }
                self.dataSource = WorktreeCreationDataSource(
                    branches: [],
                    existingBranchNames: existingBranches
                )
                self.updateFilterCounts()
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

        setupBranchNameField()
        setupToolbarRow()
        setupFilterTabs()
        setupSearchField()
        setupTableView()
        setupFooter()
        layoutViews()
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
        baseBranchPopup.target = self
        baseBranchPopup.action = #selector(baseBranchChanged(_:))
        toolbarContainer.addSubview(baseBranchPopup)

        // Create hint label
        createHintLabel.translatesAutoresizingMaskIntoConstraints = false
        createHintLabel.stringValue = "\u{2318}\u{23CE} to create"
        createHintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        createHintLabel.textColor = .tertiaryLabelColor
        createHintLabel.isEditable = false
        createHintLabel.isBordered = false
        createHintLabel.backgroundColor = .clear
        toolbarContainer.addSubview(createHintLabel)

        // Separator
        toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolbarSeparator.boxType = .custom
        toolbarSeparator.fillColor = .separatorColor
        containerView.addSubview(toolbarSeparator)

        NSLayoutConstraint.activate([
            projectPopup.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: Layout.panelPaddingH),
            projectPopup.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            baseBranchPopup.leadingAnchor.constraint(equalTo: projectPopup.trailingAnchor, constant: 8),
            baseBranchPopup.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            createHintLabel.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -Layout.panelPaddingH),
            createHintLabel.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
        ])
    }

    // MARK: - Filter Tabs

    private func setupFilterTabs() {
        filterTabsContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(filterTabsContainer)

        filterSegment.translatesAutoresizingMaskIntoConstraints = false
        filterSegment.segmentCount = 2
        filterSegment.setLabel("All 0", forSegment: 0)
        filterSegment.setLabel("Worktrees 0", forSegment: 1)
        filterSegment.setTag(FilterTab.all.rawValue, forSegment: 0)
        filterSegment.setTag(FilterTab.worktrees.rawValue, forSegment: 1)
        filterSegment.segmentStyle = .automatic
        filterSegment.font = .systemFont(ofSize: 12)
        filterSegment.selectSegment(withTag: FilterTab.all.rawValue)
        filterSegment.target = self
        filterSegment.action = #selector(filterTabChanged(_:))
        filterTabsContainer.addSubview(filterSegment)

        filterSeparator.translatesAutoresizingMaskIntoConstraints = false
        filterSeparator.boxType = .custom
        filterSeparator.fillColor = .separatorColor
        containerView.addSubview(filterSeparator)

        NSLayoutConstraint.activate([
            filterSegment.leadingAnchor.constraint(equalTo: filterTabsContainer.leadingAnchor, constant: Layout.panelPaddingH),
            filterSegment.centerYAnchor.constraint(equalTo: filterTabsContainer.centerYAnchor),
        ])
    }

    // MARK: - Search Field

    private func setupSearchField() {
        searchFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(searchFieldContainer)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = .localized("Search branches...")
        searchField.font = .systemFont(ofSize: 12, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchFieldContainer.addSubview(searchField)

        searchSeparator.translatesAutoresizingMaskIntoConstraints = false
        searchSeparator.boxType = .custom
        searchSeparator.fillColor = .separatorColor
        containerView.addSubview(searchSeparator)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchFieldContainer.leadingAnchor, constant: Layout.panelPaddingH),
            searchField.trailingAnchor.constraint(equalTo: searchFieldContainer.trailingAnchor, constant: -Layout.panelPaddingH),
            searchField.centerYAnchor.constraint(equalTo: searchFieldContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),
        ])
    }

    // MARK: - Table View

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branches"))
        column.title = ""
        column.width = Layout.panelWidth
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

    // MARK: - Footer

    private func setupFooter() {
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(footerContainer)

        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .custom
        footerSeparator.fillColor = .separatorColor
        footerContainer.addSubview(footerSeparator)

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

            pathLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.panelPaddingH),
            pathLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -Layout.panelPaddingH),
            pathLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
        ])
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Layout

    private func layoutViews() {
        let scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: Layout.rowHeight)
        self.scrollHeightConstraint = scrollHeight

        NSLayoutConstraint.activate([
            // Branch name field
            branchNameField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.branchNameTopPadding),
            branchNameField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelPaddingH),
            branchNameField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelPaddingH),
            branchNameField.heightAnchor.constraint(equalToConstant: Layout.branchNameHeight),

            // Toolbar container
            toolbarContainer.topAnchor.constraint(equalTo: branchNameField.bottomAnchor, constant: Layout.branchNameBottomGap),
            toolbarContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: Layout.toolbarHeight),

            // Toolbar separator
            toolbarSeparator.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            toolbarSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarSeparator.heightAnchor.constraint(equalToConstant: Layout.toolbarSepHeight),

            // Filter tabs container
            filterTabsContainer.topAnchor.constraint(equalTo: toolbarSeparator.bottomAnchor),
            filterTabsContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            filterTabsContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            filterTabsContainer.heightAnchor.constraint(equalToConstant: Layout.filterTabsHeight),

            // Filter separator
            filterSeparator.topAnchor.constraint(equalTo: filterTabsContainer.bottomAnchor),
            filterSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            filterSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            filterSeparator.heightAnchor.constraint(equalToConstant: Layout.filterSepHeight),

            // Search field container
            searchFieldContainer.topAnchor.constraint(equalTo: filterSeparator.bottomAnchor),
            searchFieldContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            searchFieldContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            searchFieldContainer.heightAnchor.constraint(equalToConstant: Layout.searchPaddingV + Layout.searchFieldHeight + Layout.searchPaddingV),

            // Search separator
            searchSeparator.topAnchor.constraint(equalTo: searchFieldContainer.bottomAnchor),
            searchSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            searchSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            searchSeparator.heightAnchor.constraint(equalToConstant: Layout.searchSepHeight),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: searchSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollHeight,

            // Footer
            footerContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            footerContainer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
        ])
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel = window else { return }

        let panelHeight = computePanelHeight()
        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.midX - Layout.panelWidth / 2
            let y = mainFrame.maxY - panelHeight - Layout.panelTopOffset
            panel.setFrame(NSRect(x: x, y: y, width: Layout.panelWidth, height: panelHeight), display: true)
        } else {
            panel.setFrame(NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelHeight), display: true)
            panel.center()
        }
    }

    private func computePanelHeight() -> CGFloat {
        let tableHeight = computeTableHeight()
        return Layout.fixedOverhead + tableHeight
    }

    private func computeTableHeight() -> CGFloat {
        if rows.isEmpty {
            return Layout.rowHeight // minimum 1 row
        }
        // Calculate height respecting different row heights, capped at maxVisibleRows equivalent
        var totalHeight: CGFloat = 0
        var visibleCount = 0
        for row in rows {
            let rowH: CGFloat
            switch row {
            case .sectionHeader: rowH = Layout.sectionHeaderHeight
            case .branch: rowH = Layout.rowHeight
            }
            if totalHeight + rowH > CGFloat(Layout.maxVisibleRows) * Layout.rowHeight {
                break
            }
            totalHeight += rowH
            visibleCount += 1
        }
        return max(totalHeight, Layout.rowHeight)
    }

    private func resizePanel() {
        guard let panel = window else { return }
        let panelHeight = computePanelHeight()
        let tableHeight = computeTableHeight()

        // Update scroll height constraint
        scrollHeightConstraint?.constant = tableHeight

        var frame = panel.frame
        let heightDiff = panelHeight - frame.height
        frame.origin.y -= heightDiff
        frame.size.height = panelHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Populate Popups

    private func populateProjectPopup() {
        projectPopup.removeAllItems()
        for project in projects {
            projectPopup.addItem(withTitle: project.name)
        }
        // Select current project
        if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
            projectPopup.selectItem(at: idx)
        }
    }

    private func populateBaseBranchPopup() {
        guard let ds = dataSource else { return }
        baseBranchPopup.removeAllItems()
        let branchNames = ds.localBranchNames
        if branchNames.isEmpty {
            baseBranchPopup.addItem(withTitle: "\u{2387} main")
        } else {
            for name in branchNames {
                baseBranchPopup.addItem(withTitle: "\u{2387} \(name)")
            }
            // Select default
            let defaultBranch = ds.defaultBaseBranch
            if let idx = branchNames.firstIndex(of: defaultBranch) {
                baseBranchPopup.selectItem(at: idx)
            }
        }
    }

    // MARK: - Filter & Results

    private func updateFilterCounts() {
        let totalCount = dataSource?.totalBranchCount ?? 0
        let worktreeCount = dataSource?.worktreeBranchCount ?? 0
        filterSegment.setLabel("All \(totalCount)", forSegment: 0)
        filterSegment.setLabel("Worktrees \(worktreeCount)", forSegment: 1)
    }

    private func updateResults() {
        let query = searchField.stringValue
        let grouped = dataSource?.filteredGrouped(query: query)
            ?? (local: [], remote: [])

        // Apply filter tab
        let filteredLocal: [BranchSuggestion]
        let filteredRemote: [BranchSuggestion]
        switch activeFilterTab {
        case .all:
            filteredLocal = grouped.local
            filteredRemote = grouped.remote
        case .worktrees:
            filteredLocal = grouped.local.filter(\.inUse)
            filteredRemote = grouped.remote.filter(\.inUse)
        }

        // Build flat rows — only show REMOTE header when remote branches present
        var newRows: [PanelRow] = []
        for s in filteredLocal {
            newRows.append(.branch(s))
        }
        if !filteredRemote.isEmpty {
            newRows.append(.sectionHeader("REMOTE"))
            for s in filteredRemote {
                newRows.append(.branch(s))
            }
        }

        rows = newRows

        // Select first branch row
        selectedIndex = rows.firstIndex(where: { if case .branch = $0 { return true }; return false }) ?? -1

        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        updatePathPreview()
        resizePanel()
    }

    // MARK: - Path Preview

    private func updatePathPreview() {
        let branchText = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        if branchText.isEmpty {
            pathLabel.stringValue = ""
        } else {
            let projectName = currentProjectName()
            pathLabel.stringValue = WorktreeCreationDataSource.previewPath(
                projectName: projectName,
                branchName: branchText
            )
        }
    }

    private func currentProjectName() -> String {
        if let id = selectedProjectId,
           let project = projects.first(where: { $0.id == id }) {
            return project.name
        }
        return ""
    }

    // MARK: - Confirm

    private func confirmInput() {
        let branchText = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branchText.isEmpty else { return }

        let template = TemplateRegistry.basic

        if isExistingBranch {
            // Using an existing branch — no base branch needed
            dismiss()
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: branchText,
                isNewBranch: false,
                baseBranch: nil,
                template: template
            ))
            return
        }

        // Check if typed text exactly matches an existing branch
        if let match = dataSource?.exactMatch(for: branchText) {
            dismiss()
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: match.name,
                isNewBranch: false,
                baseBranch: nil,
                template: template
            ))
            return
        }

        // New branch — use base branch from popup
        let baseBranch = selectedBaseBranch()
        dismiss()
        onCreateWorktree?(WorktreeCreationRequest(
            branchName: branchText,
            isNewBranch: true,
            baseBranch: baseBranch,
            template: template
        ))
    }

    private func selectedBaseBranch() -> String {
        let title = baseBranchPopup.titleOfSelectedItem ?? ""
        // Strip the branch icon prefix
        let stripped = title.hasPrefix("\u{2387} ") ? String(title.dropFirst(2)) : title
        return stripped.isEmpty ? (dataSource?.defaultBaseBranch ?? "main") : stripped
    }

    /// Fill branch name from a selected suggestion.
    private func selectBranchFromList(at index: Int) {
        guard index >= 0, index < rows.count,
              case .branch(let suggestion) = rows[index] else { return }

        let info = suggestion.info
        let name = info.isRemote ? info.displayName : info.name
        branchNameField.stringValue = name
        isExistingBranch = true
        baseBranchPopup.isEnabled = false
        updatePathPreview()
    }

    // MARK: - Selection Movement

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

    @objc private func baseBranchChanged(_ sender: NSPopUpButton) {
        updatePathPreview()
    }

    @objc private func filterTabChanged(_ sender: NSSegmentedControl) {
        let tag = sender.selectedTag()
        activeFilterTab = FilterTab(rawValue: tag) ?? .all
        updateResults()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .branch = rows[row] else { return }
        selectedIndex = row
        selectBranchFromList(at: row)
    }

    // MARK: - Helpers

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let seconds = Int(interval)
        if seconds < 60 { return .localized("now") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: .localized("%dm"), minutes) }
        let hours = minutes / 60
        if hours < 24 { return String(format: .localized("%dh"), hours) }
        let days = hours / 24
        if days < 30 { return String(format: .localized("%dd"), days) }
        let months = days / 30
        if months < 12 { return String(format: .localized("%dmo"), months) }
        let years = days / 365
        return String(format: .localized("%dy"), years)
    }
}

// MARK: - NSTextFieldDelegate + NSSearchFieldDelegate

extension WorktreeCreationController: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === branchNameField {
            // User typing resets existing branch selection
            if isExistingBranch {
                isExistingBranch = false
                baseBranchPopup.isEnabled = true
            }
            updatePathPreview()
        } else if field === searchField {
            updateResults()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === branchNameField {
            return handleBranchNameCommand(commandSelector)
        }
        if control === searchField {
            return handleSearchFieldCommand(commandSelector)
        }
        return false
    }

    private func handleBranchNameCommand(_ commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmInput()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            window?.makeFirstResponder(searchField)
            return true
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
            // Enter in search field: select highlighted branch into the name field
            selectBranchFromList(at: selectedIndex)
            window?.makeFirstResponder(branchNameField)
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            window?.makeFirstResponder(branchNameField)
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
        }
    }

    // MARK: - Section Header

    private func makeSectionHeaderView(title: String) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .semibold)
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

        // Icon
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .tertiaryLabelColor
        let iconConfig = NSImage.SymbolConfiguration(pointSize: Layout.cellIconSize, weight: .regular)
        imageView.symbolConfiguration = iconConfig
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

        // In-use checkmark (rightmost)
        if suggestion.inUse {
            let checkLabel = NSTextField(labelWithString: "\u{2713}")
            checkLabel.translatesAutoresizingMaskIntoConstraints = false
            checkLabel.font = .systemFont(ofSize: 11, weight: .medium)
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
            trailingConst = -8
        }

        // Commit age
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
                badgeContainer.heightAnchor.constraint(equalToConstant: 16),
            ])
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingRef, constant: trailingConst - 60).isActive = true
        } else {
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingRef, constant: trailingConst).isActive = true
        }

        return cell
    }
}
