import AppKit
import MoriCore
import MoriGit
import MoriTerminal

// MARK: - Picker Row Model

/// A row of the unified picker: section headers interleaved with actionable
/// rows. `create` and `issue` produce a new branch, so the Base row applies to
/// them; `branch` and `pr` check out something that already exists — there is
/// no base to choose.
private enum PickerRow {
    case header(String)
    /// Non-actionable explanation for a query that has no actionable rows
    /// (a branch already backing a workspace, an unknown PR URL) — without it
    /// those queries read as the panel being broken.
    case hint(String)
    /// Create a new branch with the typed name off the base branch.
    case create(name: String)
    /// Check out an existing branch (a remote one checks out its local name).
    case branch(GitBranchInfo)
    /// Check out an open PR's head branch (`gh pr checkout`).
    case pr(GitHubWorkItem)
    /// Create the derived `issue-<n>-<slug>` branch off the base branch.
    case issue(GitHubWorkItem)

    var isSelectable: Bool {
        switch self {
        case .header, .hint: return false
        case .create, .branch, .pr, .issue: return true
        }
    }

    var createsNewBranch: Bool {
        switch self {
        case .create, .issue: return true
        case .header, .hint, .branch, .pr: return false
        }
    }

    /// Identity used to preserve the highlighted row across async re-renders
    /// (a refreshed commit date or draft flag must not drop the selection).
    func matchesIdentity(_ other: PickerRow) -> Bool {
        switch (self, other) {
        case (.create, .create): return true
        case let (.branch(a), .branch(b)): return a.name == b.name
        case let (.pr(a), .pr(b)): return a.number == b.number
        case let (.issue(a), .issue(b)): return a.number == b.number
        default: return false
        }
    }
}

// MARK: - Controller

/// NSPanel driving workspace creation. The panel answers one question — which
/// branch will the new workspace check out? — with a single field over a single
/// sectioned list:
///
/// - Typing filters everything at once: existing local branches, open PRs, and
///   open issues. A non-empty name that matches no existing branch pins a
///   "Create branch" row on top, pre-selected so Enter still means "create".
/// - A name that exactly matches an existing branch selects that branch row
///   instead — checking out, never blocking on "already exists".
/// - The Base row appears only while the selected row creates a new branch
///   (create / issue); checking out a branch or PR has no base to choose.
///
/// The panel has a fixed frame; the list scrolls rather than resizing the
/// window.
@MainActor
final class WorktreeCreationController: NSWindowController, ThemedSurface {

    var themedWindow: NSWindow? { nil }

    // MARK: - Constants

    private static let fallbackBranch = "main"

    /// SF Symbol beats a text glyph in popup titles: the ⎇ character renders
    /// inconsistently across fonts, and a menu-item image tints with appearance.
    private static let branchMenuImage: NSImage? = NSImage(
        systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: - Callbacks

    /// Called when the user confirms worktree creation.
    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?

    /// Called to fetch branches asynchronously.
    var fetchBranches: ((_ projectId: UUID, _ repoPath: String) async throws -> [GitBranchInfo])?

    /// Called to prefetch open GitHub issues + PRs. Returns `[]` for remote/SSH
    /// projects (gh is local-only).
    var fetchGitHubItems: ((_ projectId: UUID, _ repoPath: String) async -> [GitHubWorkItem])?

    /// Called when the user switches projects in the popup.
    var onProjectChanged: ((UUID) -> Void)?

    // MARK: - State

    private var dataSource: WorktreeCreationDataSource?
    private var projects: [Project] = []
    private var selectedProjectId: UUID?
    private var repoPath: String = ""

    /// Branches already backing a workspace in the current project — excluded
    /// from the branch section (and PRs whose head is such a branch).
    private var excludedBranches: Set<String> = []

    private var fetchGeneration: Int = 0
    private var githubFetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // Prefetched GitHub issues + PRs (volatile picker data).
    private var githubItems: [GitHubWorkItem] = []

    // Unified picker list + highlight (-1 == nothing selected).
    private var pickerRows: [PickerRow] = []
    private var selectedPickerRow: Int = -1

    /// Collapsed to zero while the Base row is hidden — `isHidden` alone leaves
    /// dead space between the name field and the list.
    private var baseRowTopConstraint: NSLayoutConstraint?
    private var baseRowHeightConstraint: NSLayoutConstraint?

    // MARK: - Views

    private let containerView = NSView()

    // Header.
    private let titleLabel = NSTextField(labelWithString: "")
    private let projectPopup = NSPopUpButton()
    private let closeButton = NSButton()

    // Content — one field, an on-demand Base row, one sectioned list.
    private let contentContainer = NSView()
    private let branchNameField = NSTextField()
    private let baseLabel = NSTextField(labelWithString: "")
    private let baseBranchPopup = NSPopUpButton()
    private let pickerScrollView = NSScrollView()
    private let pickerTable = NSTableView()

    // Footer.
    private let createButton = NSButton()

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 520
        static let panelHeight: CGFloat = 420
        static let panelTopOffset: CGFloat = 80
        static let cornerRadius: CGFloat = 10

        static let padH: CGFloat = 16
        static let padTop: CGFloat = 14
        static let padBottom: CGFloat = 14

        static let headerHeight: CGFloat = 22
        static let projectPopupWidth: CGFloat = 180
        static let headerToContentGap: CGFloat = 12
        static let contentToFooterGap: CGFloat = 12
        static let footerHeight: CGFloat = 32

        static let fieldHeight: CGFloat = 28
        static let baseRowTopGap: CGFloat = 12
        static let baseRowHeight: CGFloat = 22
        static let listTopGap: CGFloat = 12
        static let rowHeight: CGFloat = 28
        static let sectionHeaderRowHeight: CGFloat = 24

        /// Content-width priority for popups: below the required edge pins so a
        /// long branch/project title truncates instead of driving the frame wide.
        static let popupCompressionResistance = NSLayoutConstraint.Priority(250)
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

    /// Show the panel for a given project, pre-loading branch and GitHub data.
    func show(
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String,
        existingWorktreeBranches: Set<String>
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath
        self.excludedBranches = existingWorktreeBranches

        resetForShow()

        positionPanel()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(branchNameField)

        fetchBranchesAsync(repoPath: repoPath)
        fetchGitHubItemsAsync(repoPath: repoPath)
    }

    /// Lightweight refresh when the user switches projects — re-fetches data
    /// without re-positioning, re-theming, or changing the active tab.
    func refresh(
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String,
        existingWorktreeBranches: Set<String>
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath
        self.excludedBranches = existingWorktreeBranches

        resetInputs()
        populateProjectPopup()
        resetBaseBranchPopup()

        fetchBranchesAsync(repoPath: repoPath)
        fetchGitHubItemsAsync(repoPath: repoPath)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    // MARK: - Theme

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
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

        setupHeader()
        setupContent()
        setupFooter()
        layoutChrome()

        updateCreateButton()
    }

    private func setupKeyEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.window, panel.isVisible else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ⌘⏎ from anywhere: confirm.
            if event.keyCode == 36, mods.contains(.command) {
                self.confirm()
                return nil
            }
            // Esc from anywhere: dismiss.
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    // MARK: - Header

    private func setupHeader() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = .localized("New Workspace")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        containerView.addSubview(titleLabel)

        projectPopup.translatesAutoresizingMaskIntoConstraints = false
        projectPopup.controlSize = .small
        projectPopup.font = .systemFont(ofSize: 12)
        projectPopup.target = self
        projectPopup.action = #selector(projectChanged(_:))
        (projectPopup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        projectPopup.setContentCompressionResistancePriority(
            Layout.popupCompressionResistance, for: .horizontal
        )
        containerView.addSubview(projectPopup)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: .localized("Close")
        )
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked(_:))
        containerView.addSubview(closeButton)
    }

    // MARK: - Content

    private func setupContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentContainer)

        branchNameField.translatesAutoresizingMaskIntoConstraints = false
        branchNameField.placeholderString = .localized("Branch name, or search branches, PRs, issues")
        branchNameField.font = .systemFont(ofSize: 14)
        branchNameField.isBordered = true
        branchNameField.bezelStyle = .roundedBezel
        branchNameField.focusRingType = .none
        branchNameField.delegate = self
        contentContainer.addSubview(branchNameField)

        baseLabel.translatesAutoresizingMaskIntoConstraints = false
        baseLabel.stringValue = .localized("Base")
        baseLabel.font = .systemFont(ofSize: 12)
        baseLabel.textColor = .secondaryLabelColor
        baseLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentContainer.addSubview(baseLabel)

        baseBranchPopup.translatesAutoresizingMaskIntoConstraints = false
        baseBranchPopup.controlSize = .regular
        baseBranchPopup.font = .systemFont(ofSize: 12)
        (baseBranchPopup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        baseBranchPopup.setContentCompressionResistancePriority(
            Layout.popupCompressionResistance, for: .horizontal
        )
        contentContainer.addSubview(baseBranchPopup)

        configureList(pickerTable, scroll: pickerScrollView, in: contentContainer)
        pickerTable.target = self
        pickerTable.action = #selector(pickerRowClicked(_:))
        pickerTable.doubleAction = #selector(pickerRowDoubleClicked(_:))

        resetBaseBranchPopup()

        // The Base row collapses while the selected row checks something out —
        // there is no base to choose for an existing branch or a PR.
        let baseTop = baseBranchPopup.topAnchor.constraint(
            equalTo: branchNameField.bottomAnchor, constant: Layout.baseRowTopGap
        )
        let baseHeight = baseBranchPopup.heightAnchor.constraint(equalToConstant: Layout.baseRowHeight)
        baseRowTopConstraint = baseTop
        baseRowHeightConstraint = baseHeight

        NSLayoutConstraint.activate([
            branchNameField.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            branchNameField.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            branchNameField.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            branchNameField.heightAnchor.constraint(equalToConstant: Layout.fieldHeight),

            baseLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            baseLabel.centerYAnchor.constraint(equalTo: baseBranchPopup.centerYAnchor),

            baseTop,
            baseHeight,
            baseBranchPopup.leadingAnchor.constraint(equalTo: baseLabel.trailingAnchor, constant: 8),
            baseBranchPopup.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            pickerScrollView.topAnchor.constraint(equalTo: baseBranchPopup.bottomAnchor, constant: Layout.listTopGap),
            pickerScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pickerScrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pickerScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        setBaseRowVisible(false)
    }

    private func configureList(_ table: NSTableView, scroll: NSScrollView, in parent: NSView) {
        table.translatesAutoresizingMaskIntoConstraints = false
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = Layout.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.gridStyleMask = []
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        // Subtle rounded fill so the list reads as a contained region instead of
        // rows floating on the panel background.
        scroll.drawsBackground = true
        scroll.backgroundColor = .quaternarySystemFill
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.masksToBounds = true
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        parent.addSubview(scroll)
    }

    // MARK: - Footer

    private func setupFooter() {
        // Prominent primary action. Deliberately no keyEquivalent = "\r": a default
        // button's performKeyEquivalent would intercept Enter before the field
        // editor, moving confirm off the delegate path. Enter and ⌘⏎ stay with the
        // field delegate / event monitor; the button confirms via click.
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.bezelStyle = .rounded
        createButton.controlSize = .large
        createButton.bezelColor = .controlAccentColor
        createButton.setButtonType(.momentaryPushIn)
        createButton.target = self
        createButton.action = #selector(createButtonClicked(_:))
        createButton.setContentHuggingPriority(.required, for: .horizontal)
        createButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (createButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        createButton.attributedTitle = NSAttributedString(
            string: .localized("Create Workspace"),
            attributes: [
                .foregroundColor: NSColor.alternateSelectedControlTextColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
        )
        containerView.addSubview(createButton)
    }

    // MARK: - Chrome Layout

    private func layoutChrome() {
        let padH = Layout.padH

        NSLayoutConstraint.activate([
            // Header row.
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.padTop),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padH),
            titleLabel.centerYAnchor.constraint(equalTo: projectPopup.centerYAnchor),

            closeButton.centerYAnchor.constraint(equalTo: projectPopup.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            projectPopup.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.padTop),
            projectPopup.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            projectPopup.widthAnchor.constraint(equalToConstant: Layout.projectPopupWidth),
            projectPopup.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            projectPopup.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            // Content between the header and the footer.
            contentContainer.topAnchor.constraint(equalTo: projectPopup.bottomAnchor, constant: Layout.headerToContentGap),
            contentContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padH),
            contentContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
            contentContainer.bottomAnchor.constraint(equalTo: createButton.topAnchor, constant: -Layout.contentToFooterGap),

            // Footer.
            createButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
            createButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.padBottom),
            createButton.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
            createButton.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: padH),
        ])
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel = window else { return }
        let size = NSSize(width: Layout.panelWidth, height: Layout.panelHeight)

        if let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.midX - size.width / 2
            let y = mainFrame.maxY - size.height - Layout.panelTopOffset
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        } else {
            panel.setFrame(NSRect(origin: .zero, size: size), display: true)
            panel.center()
        }
    }

    // MARK: - Reset

    private func resetForShow() {
        resetInputs()
        populateProjectPopup()
        resetBaseBranchPopup()
    }

    private func resetInputs() {
        branchNameField.stringValue = ""
        dataSource = nil
        githubItems = []
        rebuildPickerRows(preserveSelection: false)
    }

    // MARK: - Fetching

    private func fetchBranchesAsync(repoPath: String) {
        fetchGeneration += 1
        let generation = fetchGeneration
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
            guard self.fetchGeneration == generation else { return }
            self.dataSource = WorktreeCreationDataSource(branches: branches)
            self.populateBaseBranchPopup()
            self.rebuildPickerRows(preserveSelection: true)
        }
    }

    private func fetchGitHubItemsAsync(repoPath: String) {
        githubItems = []
        githubFetchGeneration += 1
        let generation = githubFetchGeneration
        Task { [weak self] in
            guard let self, let projectId = self.selectedProjectId else { return }
            let items = await self.fetchGitHubItems?(projectId, repoPath) ?? []
            guard self.githubFetchGeneration == generation else { return }
            self.githubItems = items
            self.rebuildPickerRows(preserveSelection: true)
        }
    }

    // MARK: - Popups

    private func populateProjectPopup() {
        projectPopup.removeAllItems()
        for project in projects {
            projectPopup.addItem(withTitle: project.name)
        }
        if let idx = projects.firstIndex(where: { $0.id == selectedProjectId }) {
            projectPopup.selectItem(at: idx)
        }
    }

    private func resetBaseBranchPopup() {
        baseBranchPopup.removeAllItems()
        addBaseBranchItem(Self.fallbackBranch)
    }

    private func populateBaseBranchPopup() {
        guard let ds = dataSource else { return }
        baseBranchPopup.removeAllItems()
        let names = ds.localBranchNames
        if names.isEmpty {
            addBaseBranchItem(Self.fallbackBranch)
        } else {
            for name in names {
                addBaseBranchItem(name)
            }
            if let idx = names.firstIndex(of: ds.defaultBaseBranch) {
                baseBranchPopup.selectItem(at: idx)
            }
        }
    }

    private func addBaseBranchItem(_ name: String) {
        baseBranchPopup.addItem(withTitle: name)
        baseBranchPopup.lastItem?.representedObject = name
        baseBranchPopup.lastItem?.image = Self.branchMenuImage
    }

    private func selectedBaseBranch() -> String {
        if let name = baseBranchPopup.selectedItem?.representedObject as? String, !name.isEmpty {
            return name
        }
        return dataSource?.defaultBaseBranch ?? Self.fallbackBranch
    }

    private func setBaseRowVisible(_ visible: Bool) {
        baseLabel.isHidden = !visible
        baseBranchPopup.isHidden = !visible
        baseRowTopConstraint?.constant = visible ? Layout.baseRowTopGap : 0
        baseRowHeightConstraint?.constant = visible ? Layout.baseRowHeight : 0
    }

    // MARK: - Picker Logic

    /// React to typing: a pasted GitHub URL is normalized into a searchable
    /// reference first, then the list rebuilds around the new query.
    private func handleNameChange() {
        let text = branchNameField.stringValue

        if let (kind, number) = GitHubWorkItem.parseURL(text) {
            // A known item becomes a `#n` query so its row filters in and gets
            // selected below. An issue outside the prefetched list still works
            // as a derived branch name; an unknown PR cannot be checked out
            // (no head ref), so its URL is left in place matching nothing.
            if githubItems.contains(where: { $0.kind == kind && $0.number == number }) {
                branchNameField.stringValue = "#\(number)"
            } else if kind == .issue {
                branchNameField.stringValue = GitHubWorkItem.issueBranchName(number: number, title: "")
            }
        }

        rebuildPickerRows(preserveSelection: false)
    }

    private func rebuildPickerRows(preserveSelection: Bool) {
        let previous: PickerRow? = (preserveSelection && selectedPickerRow >= 0 && selectedPickerRow < pickerRows.count)
            ? pickerRows[selectedPickerRow] : nil

        pickerRows = buildPickerRows()
        pickerTable.reloadData()

        if let previous, let idx = pickerRows.firstIndex(where: { $0.matchesIdentity(previous) }) {
            selectedPickerRow = idx
        } else {
            selectedPickerRow = defaultSelection()
        }
        applyPickerSelection()
    }

    /// Create → Branches → Pull Requests → Issues, all filtered by one query.
    private func buildPickerRows() -> [PickerRow] {
        let query = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        let referencedNumber = hashNumber(in: query)
        let exactMatch = dataSource?.exactMatch(for: query)
        var rows: [PickerRow] = []

        if let (kind, number) = GitHubWorkItem.parseURL(query) {
            // Only an unknown PR URL survives handleNameChange un-rewritten; a
            // URL is never a valid branch name, so explain instead of offering
            // a doomed create row.
            if kind == .pullRequest {
                rows.append(.hint(String(
                    format: .localized("PR #%d isn’t among the open pull requests — it may be closed, merged, or beyond the fetched list."),
                    number
                )))
            }
        } else if !query.isEmpty, referencedNumber == nil, exactMatch == nil {
            // A name that is neither an existing branch nor a `#123` reference
            // can be created.
            rows.append(.create(name: query))
        } else if let exactMatch, !exactMatch.isRemote, excludedBranches.contains(exactMatch.name) {
            // The typed branch exists but already backs a workspace: both the
            // create row and its branch row are suppressed, so say why.
            rows.append(.hint(String(
                format: .localized("“%@” is already open as a workspace."),
                exactMatch.name
            )))
        }

        var branches = dataSource?.checkoutBranches(excluding: excludedBranches, matching: query) ?? []
        // An exact match on a remote-only branch stays selectable even though
        // the list is local: typing its full name checks it out.
        if let match = exactMatch, match.isRemote,
           !branches.contains(where: { $0.name == match.name }) {
            branches.insert(match, at: 0)
        }
        if !branches.isEmpty {
            rows.append(.header(.localized("Branches")))
            rows.append(contentsOf: branches.map { .branch($0) })
        }

        func matches(_ item: GitHubWorkItem) -> Bool {
            if let referencedNumber { return item.number == referencedNumber }
            guard !q.isEmpty else { return true }
            let haystack = "#\(item.number) \(item.title) \(item.headRefName ?? "")".lowercased()
            return haystack.contains(q)
        }

        let prs = githubItems.filter { item in
            guard item.kind == .pullRequest else { return false }
            if let head = item.headRefName, !head.isEmpty, excludedBranches.contains(head) { return false }
            return matches(item)
        }
        if !prs.isEmpty {
            rows.append(.header(.localized("Pull Requests")))
            rows.append(contentsOf: prs.map { .pr($0) })
        }

        let issues = githubItems.filter { $0.kind == .issue && matches($0) }
        if !issues.isEmpty {
            rows.append(.header(.localized("Issues")))
            rows.append(contentsOf: issues.map { .issue($0) })
        }
        return rows
    }

    /// The row Enter should act on without arrowing: the create row when the
    /// typed name is new, the matching branch row when it already exists, the
    /// referenced item for a `#123` query. An empty query selects nothing so
    /// Enter can't fire on an arbitrary first row.
    private func defaultSelection() -> Int {
        let query = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return -1 }

        if case .create? = pickerRows.first { return 0 }

        if let referencedNumber = hashNumber(in: query),
           let idx = pickerRows.firstIndex(where: {
               switch $0 {
               case let .pr(item), let .issue(item): return item.number == referencedNumber
               default: return false
               }
           }) {
            return idx
        }

        if let match = dataSource?.exactMatch(for: query),
           let idx = pickerRows.firstIndex(where: {
               if case let .branch(branch) = $0 { return branch.name == match.name }
               return false
           }) {
            return idx
        }
        return -1
    }

    private func movePickerSelection(by delta: Int) {
        let selectable = pickerRows.indices.filter { pickerRows[$0].isSelectable }
        guard !selectable.isEmpty else { return }
        if let current = selectable.firstIndex(of: selectedPickerRow) {
            let next = max(0, min(selectable.count - 1, current + delta))
            selectedPickerRow = selectable[next]
        } else {
            selectedPickerRow = delta >= 0 ? selectable[0] : selectable[selectable.count - 1]
        }
        applyPickerSelection()
    }

    private func applyPickerSelection() {
        defer {
            updateBaseRowVisibility()
            updateCreateButton()
        }
        guard selectedPickerRow >= 0, selectedPickerRow < pickerRows.count else {
            pickerTable.deselectAll(nil)
            return
        }
        pickerTable.selectRowIndexes(IndexSet(integer: selectedPickerRow), byExtendingSelection: false)
        pickerTable.scrollRowToVisible(selectedPickerRow)
    }

    private func updateBaseRowVisibility() {
        let selected: PickerRow? = (selectedPickerRow >= 0 && selectedPickerRow < pickerRows.count)
            ? pickerRows[selectedPickerRow] : nil
        setBaseRowVisible(selected?.createsNewBranch ?? false)
    }

    /// A bare `#123` reference (trimmed, digits only).
    private func hashNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    // MARK: - Create Button

    private func updateCreateButton() {
        createButton.isEnabled = selectedPickerRow >= 0
            && selectedPickerRow < pickerRows.count
            && pickerRows[selectedPickerRow].isSelectable
    }

    // MARK: - Confirm

    private func confirm() {
        guard selectedPickerRow >= 0, selectedPickerRow < pickerRows.count else { return }
        let row = pickerRows[selectedPickerRow]
        guard row.isSelectable, let projectId = selectedProjectId else { return }
        dismiss()

        switch row {
        case .header, .hint:
            break
        case let .create(name):
            onCreateWorktree?(WorktreeCreationRequest(
                projectId: projectId,
                branchName: name,
                isNewBranch: true,
                baseBranch: selectedBaseBranch(),
                origin: .branch
            ))
        case let .branch(branch):
            onCreateWorktree?(WorktreeCreationRequest(
                projectId: projectId,
                branchName: branch.isRemote ? branch.displayName : branch.name,
                isNewBranch: false,
                baseBranch: nil,
                origin: .branch
            ))
        case let .pr(item):
            // branchName is ignored for a PR origin — the manager takes the
            // branch from headRef (and rejects an empty one).
            let head = item.headRefName ?? ""
            onCreateWorktree?(WorktreeCreationRequest(
                projectId: projectId,
                branchName: head,
                isNewBranch: false,
                baseBranch: nil,
                origin: .pullRequest(number: item.number, headRef: head)
            ))
        case let .issue(item):
            onCreateWorktree?(WorktreeCreationRequest(
                projectId: projectId,
                branchName: GitHubWorkItem.issueBranchName(number: item.number, title: item.title),
                isNewBranch: true,
                baseBranch: selectedBaseBranch(),
                origin: .issue(number: item.number)
            ))
        }
    }

    // MARK: - Actions

    @objc private func pickerRowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < pickerRows.count, pickerRows[row].isSelectable else { return }
        selectedPickerRow = row
        applyPickerSelection()
        // Keep the field first responder so Enter still confirms via its delegate.
        window?.makeFirstResponder(branchNameField)
    }

    @objc private func pickerRowDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < pickerRows.count, pickerRows[row].isSelectable else { return }
        selectedPickerRow = row
        confirm()
    }

    @objc private func createButtonClicked(_ sender: NSButton) {
        confirm()
    }

    @objc private func closeButtonClicked(_ sender: NSButton) {
        dismiss()
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
        guard let field = obj.object as? NSTextField, field === branchNameField else { return }
        handleNameChange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === branchNameField else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            movePickerSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            movePickerSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            confirm()
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard !baseBranchPopup.isHidden else { return false }
            window?.makeFirstResponder(baseBranchPopup)
            return true
        default:
            return false
        }
    }
}

// MARK: - Tables

extension WorktreeCreationController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        pickerRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < pickerRows.count else { return nil }
        switch pickerRows[row] {
        case let .header(title): return makeHeaderCell(title)
        case let .hint(text): return makeHintCell(text)
        case let .create(name): return makeCreateCell(name)
        case let .branch(branch): return makeBranchCell(branch)
        case let .pr(item): return makePRCell(item)
        case let .issue(item): return makeIssueCell(item)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row >= 0 && row < pickerRows.count && pickerRows[row].isSelectable
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < pickerRows.count else { return Layout.rowHeight }
        if case .header = pickerRows[row] { return Layout.sectionHeaderRowHeight }
        return Layout.rowHeight
    }

    /// Mirror mouse-driven selection back into the model so Enter and the
    /// create button track it.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as AnyObject === pickerTable else { return }
        let row = pickerTable.selectedRow
        if row >= 0, row < pickerRows.count, pickerRows[row].isSelectable {
            selectedPickerRow = row
            updateBaseRowVisibility()
            updateCreateButton()
        }
    }

    // MARK: Cell Builders

    private func symbolIcon(_ name: String) -> NSImageView {
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        return icon
    }

    private func primaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func dimLabel(_ text: String, monospacedDigits: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func makeHeaderCell(_ title: String) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title.uppercased())
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    private func makeHintCell(_ text: String) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("info.circle")
        let label = primaryLabel(text)
        label.textColor = .secondaryLabelColor
        cell.addSubview(icon)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeCreateCell(_ name: String) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("plus.circle")
        let title = primaryLabel(String(format: .localized("Create branch “%@”"), name))
        cell.addSubview(icon)
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeIssueCell(_ item: GitHubWorkItem) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("smallcircle.filled.circle")
        let number = dimLabel("#\(item.number)", monospacedDigits: true)
        let title = primaryLabel(item.title)
        // The branch the row will create, so selecting an issue is not a surprise.
        let branchLabel = dimLabel(GitHubWorkItem.issueBranchName(number: item.number, title: item.title))
        branchLabel.lineBreakMode = .byTruncatingMiddle
        branchLabel.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)

        for view in [icon, number, title, branchLabel] { cell.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            number.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            number.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(lessThanOrEqualTo: branchLabel.leadingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            branchLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            branchLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeBranchCell(_ branch: GitBranchInfo) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("arrow.triangle.branch")
        let name = primaryLabel(branch.name)
        cell.addSubview(icon)
        cell.addSubview(name)

        var nameTrailing = cell.trailingAnchor
        if let date = branch.commitDate {
            let dateLabel = dimLabel(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))
            cell.addSubview(dateLabel)
            NSLayoutConstraint.activate([
                dateLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                dateLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            nameTrailing = dateLabel.leadingAnchor
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: nameTrailing, constant: -8),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makePRCell(_ item: GitHubWorkItem) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("arrow.triangle.pull")
        let number = dimLabel("#\(item.number)", monospacedDigits: true)
        let title = primaryLabel(item.title)

        cell.addSubview(icon)
        cell.addSubview(number)
        cell.addSubview(title)

        var constraints: [NSLayoutConstraint] = [
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            number.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            number.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ]

        let head = item.headRefName ?? ""
        if head.isEmpty {
            constraints.append(title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8))
        } else {
            let headLabel = dimLabel(head)
            headLabel.lineBreakMode = .byTruncatingMiddle
            headLabel.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
            cell.addSubview(headLabel)
            constraints.append(contentsOf: [
                title.trailingAnchor.constraint(lessThanOrEqualTo: headLabel.leadingAnchor, constant: -8),
                headLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                headLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }
}
