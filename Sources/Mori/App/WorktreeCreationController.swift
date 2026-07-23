import AppKit
import MoriCore
import MoriGit
import MoriTerminal

// MARK: - Checkout Row Model

/// A single row in the "Check Out Existing" list: an existing local branch or an
/// open pull request (whose head branch would be checked out). PRs are just
/// "someone else's existing branch", so both live in one flat, selectable list.
private enum CheckoutRow: Equatable {
    case branch(GitBranchInfo)
    case pr(GitHubWorkItem)

    /// Identity used to preserve the highlighted row across async re-renders
    /// (a refreshed commit date or draft flag must not drop the selection).
    func matchesIdentity(_ other: CheckoutRow) -> Bool {
        switch (self, other) {
        case let (.branch(a), .branch(b)): return a.name == b.name
        case let (.pr(a), .pr(b)): return a.number == b.number
        default: return false
        }
    }
}

// MARK: - Controller

/// NSPanel driving workspace creation. The panel answers one question — which
/// branch will the new workspace check out? — split across two tabs:
///
/// - **New Branch**: type a name (or start from a GitHub issue) to `checkout -b`
///   off a base branch. If the name already names an existing branch, the panel
///   silently switches to checking it out instead of blocking.
/// - **Check Out Existing**: pick an existing local branch or an open PR's head
///   branch. Branches already backing a workspace are excluded.
///
/// The panel has a fixed frame; its two list areas scroll rather than resizing
/// the window.
@MainActor
final class WorktreeCreationController: NSWindowController {

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
    /// from the "Check Out Existing" list (and PRs whose head is such a branch).
    private var excludedBranches: Set<String> = []

    private var fetchGeneration: Int = 0
    private var githubFetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // Prefetched GitHub issues + PRs (volatile picker data).
    private var githubItems: [GitHubWorkItem] = []

    // Tab 1 issue picker (open issues only).
    private var issues: [GitHubWorkItem] = []
    /// The name auto-filled from a picked issue and the issue's number. Cleared
    /// once the user edits the name so it no longer matches the auto-fill.
    private var autofilledName: String?
    private var issueAssociation: Int?

    // Tab 2 combined list + highlight (-1 == nothing selected).
    private var checkoutRows: [CheckoutRow] = []
    private var checkoutSelectedRow: Int = -1

    private var currentTab = 0

    /// Collapsed to zero while the exists-hint is hidden — `isHidden` alone
    /// leaves dead space between the name field and the Base row.
    private var hintTopConstraint: NSLayoutConstraint?
    private var hintHeightConstraint: NSLayoutConstraint?

    // MARK: - Views

    private let containerView = NSView()

    // Header.
    private let titleLabel = NSTextField(labelWithString: "")
    private let projectPopup = NSPopUpButton()
    private let closeButton = NSButton()

    // Tab switch.
    private let segmentedControl = NSSegmentedControl()

    // Tab 1 — New Branch.
    private let newBranchContainer = NSView()
    private let branchNameField = NSTextField()
    private let existsHintLabel = NSTextField(labelWithString: "")
    private let baseLabel = NSTextField(labelWithString: "")
    private let baseBranchPopup = NSPopUpButton()
    private let issueSectionLabel = NSTextField(labelWithString: "")
    private let issuesScrollView = NSScrollView()
    private let issuesTable = NSTableView()

    // Tab 2 — Check Out Existing.
    private let checkoutContainer = NSView()
    private let filterField = NSTextField()
    private let checkoutScrollView = NSScrollView()
    private let checkoutTable = NSTableView()

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
        static let headerToSegmentGap: CGFloat = 12
        static let segmentHeight: CGFloat = 24
        static let segmentToContentGap: CGFloat = 12
        static let contentToFooterGap: CGFloat = 12
        static let footerHeight: CGFloat = 32

        static let fieldHeight: CGFloat = 28
        static let hintTopGap: CGFloat = 6
        static let hintHeight: CGFloat = 14
        static let baseRowTopGap: CGFloat = 12
        static let baseRowHeight: CGFloat = 22
        static let sectionLabelTopGap: CGFloat = 12
        static let sectionLabelHeight: CGFloat = 14
        static let listTopGap: CGFloat = 6
        static let rowHeight: CGFloat = 28

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
        existingWorktreeBranches: Set<String>,
        themeInfo: GhosttyThemeInfo
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath
        self.excludedBranches = existingWorktreeBranches

        applyTheme(themeInfo)
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

        setupHeader()
        setupSegmentedControl()
        setupNewBranchTab()
        setupCheckoutTab()
        setupFooter()
        layoutChrome()

        selectTab(0)
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

    private func setupSegmentedControl() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel(.localized("New Branch"), forSegment: 0)
        segmentedControl.setLabel(.localized("Check Out Existing"), forSegment: 1)
        segmentedControl.segmentDistribution = .fillEqually
        segmentedControl.trackingMode = .selectOne
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        containerView.addSubview(segmentedControl)
    }

    // MARK: - Tab 1 — New Branch

    private func setupNewBranchTab() {
        newBranchContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(newBranchContainer)

        branchNameField.translatesAutoresizingMaskIntoConstraints = false
        branchNameField.placeholderString = .localized("Branch name")
        branchNameField.font = .systemFont(ofSize: 14)
        branchNameField.isBordered = true
        branchNameField.bezelStyle = .roundedBezel
        branchNameField.focusRingType = .none
        branchNameField.delegate = self
        newBranchContainer.addSubview(branchNameField)

        existsHintLabel.translatesAutoresizingMaskIntoConstraints = false
        existsHintLabel.stringValue = .localized("Branch already exists — it will be checked out")
        existsHintLabel.font = .systemFont(ofSize: 11)
        existsHintLabel.textColor = .secondaryLabelColor
        existsHintLabel.lineBreakMode = .byTruncatingTail
        existsHintLabel.isHidden = true
        newBranchContainer.addSubview(existsHintLabel)

        baseLabel.translatesAutoresizingMaskIntoConstraints = false
        baseLabel.stringValue = .localized("Base")
        baseLabel.font = .systemFont(ofSize: 12)
        baseLabel.textColor = .secondaryLabelColor
        baseLabel.setContentHuggingPriority(.required, for: .horizontal)
        newBranchContainer.addSubview(baseLabel)

        baseBranchPopup.translatesAutoresizingMaskIntoConstraints = false
        baseBranchPopup.controlSize = .regular
        baseBranchPopup.font = .systemFont(ofSize: 12)
        (baseBranchPopup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        baseBranchPopup.setContentCompressionResistancePriority(
            Layout.popupCompressionResistance, for: .horizontal
        )
        newBranchContainer.addSubview(baseBranchPopup)

        issueSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        issueSectionLabel.stringValue = String.localized("Or start from an issue").uppercased()
        issueSectionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        issueSectionLabel.textColor = .tertiaryLabelColor
        issueSectionLabel.lineBreakMode = .byTruncatingTail
        newBranchContainer.addSubview(issueSectionLabel)

        configureList(issuesTable, scroll: issuesScrollView, in: newBranchContainer)
        issuesTable.target = self
        issuesTable.action = #selector(issueRowClicked(_:))

        resetBaseBranchPopup()

        let hintTop = existsHintLabel.topAnchor.constraint(equalTo: branchNameField.bottomAnchor, constant: 0)
        let hintHeight = existsHintLabel.heightAnchor.constraint(equalToConstant: 0)
        hintTopConstraint = hintTop
        hintHeightConstraint = hintHeight

        let padH: CGFloat = 0
        NSLayoutConstraint.activate([
            branchNameField.topAnchor.constraint(equalTo: newBranchContainer.topAnchor),
            branchNameField.leadingAnchor.constraint(equalTo: newBranchContainer.leadingAnchor, constant: padH),
            branchNameField.trailingAnchor.constraint(equalTo: newBranchContainer.trailingAnchor, constant: -padH),
            branchNameField.heightAnchor.constraint(equalToConstant: Layout.fieldHeight),

            hintTop,
            existsHintLabel.leadingAnchor.constraint(equalTo: newBranchContainer.leadingAnchor, constant: 2),
            existsHintLabel.trailingAnchor.constraint(equalTo: newBranchContainer.trailingAnchor),
            hintHeight,

            baseLabel.topAnchor.constraint(equalTo: existsHintLabel.bottomAnchor, constant: Layout.baseRowTopGap),
            baseLabel.leadingAnchor.constraint(equalTo: newBranchContainer.leadingAnchor),
            baseLabel.centerYAnchor.constraint(equalTo: baseBranchPopup.centerYAnchor),

            baseBranchPopup.topAnchor.constraint(equalTo: existsHintLabel.bottomAnchor, constant: Layout.baseRowTopGap),
            baseBranchPopup.leadingAnchor.constraint(equalTo: baseLabel.trailingAnchor, constant: 8),
            baseBranchPopup.trailingAnchor.constraint(equalTo: newBranchContainer.trailingAnchor),
            baseBranchPopup.heightAnchor.constraint(equalToConstant: Layout.baseRowHeight),

            issueSectionLabel.topAnchor.constraint(equalTo: baseBranchPopup.bottomAnchor, constant: Layout.sectionLabelTopGap),
            issueSectionLabel.leadingAnchor.constraint(equalTo: newBranchContainer.leadingAnchor, constant: 2),
            issueSectionLabel.trailingAnchor.constraint(equalTo: newBranchContainer.trailingAnchor),
            issueSectionLabel.heightAnchor.constraint(equalToConstant: Layout.sectionLabelHeight),

            issuesScrollView.topAnchor.constraint(equalTo: issueSectionLabel.bottomAnchor, constant: Layout.listTopGap),
            issuesScrollView.leadingAnchor.constraint(equalTo: newBranchContainer.leadingAnchor),
            issuesScrollView.trailingAnchor.constraint(equalTo: newBranchContainer.trailingAnchor),
            issuesScrollView.bottomAnchor.constraint(equalTo: newBranchContainer.bottomAnchor),
        ])
    }

    // MARK: - Tab 2 — Check Out Existing

    private func setupCheckoutTab() {
        checkoutContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(checkoutContainer)

        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.placeholderString = .localized("Filter branches and PRs")
        filterField.font = .systemFont(ofSize: 13)
        filterField.isBordered = true
        filterField.bezelStyle = .roundedBezel
        filterField.focusRingType = .none
        filterField.delegate = self
        checkoutContainer.addSubview(filterField)

        configureList(checkoutTable, scroll: checkoutScrollView, in: checkoutContainer)
        checkoutTable.target = self
        checkoutTable.action = #selector(checkoutRowClicked(_:))
        checkoutTable.doubleAction = #selector(checkoutRowDoubleClicked(_:))

        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: checkoutContainer.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: checkoutContainer.leadingAnchor),
            filterField.trailingAnchor.constraint(equalTo: checkoutContainer.trailingAnchor),
            filterField.heightAnchor.constraint(equalToConstant: Layout.fieldHeight),

            checkoutScrollView.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: Layout.listTopGap + 2),
            checkoutScrollView.leadingAnchor.constraint(equalTo: checkoutContainer.leadingAnchor),
            checkoutScrollView.trailingAnchor.constraint(equalTo: checkoutContainer.trailingAnchor),
            checkoutScrollView.bottomAnchor.constraint(equalTo: checkoutContainer.bottomAnchor),
        ])
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

            // Segmented control.
            segmentedControl.topAnchor.constraint(equalTo: projectPopup.bottomAnchor, constant: Layout.headerToSegmentGap),
            segmentedControl.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padH),
            segmentedControl.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
            segmentedControl.heightAnchor.constraint(equalToConstant: Layout.segmentHeight),

            // Footer.
            createButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
            createButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.padBottom),
            createButton.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
            createButton.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: padH),
        ])

        // Both tab containers occupy the same content area between the segmented
        // control and the footer; only one is visible at a time.
        for tab in [newBranchContainer, checkoutContainer] {
            NSLayoutConstraint.activate([
                tab.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Layout.segmentToContentGap),
                tab.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padH),
                tab.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padH),
                tab.bottomAnchor.constraint(equalTo: createButton.topAnchor, constant: -Layout.contentToFooterGap),
            ])
        }
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
        segmentedControl.selectedSegment = 0
        selectTab(0)
        resetInputs()
        populateProjectPopup()
        resetBaseBranchPopup()
    }

    private func resetInputs() {
        branchNameField.stringValue = ""
        filterField.stringValue = ""
        autofilledName = nil
        issueAssociation = nil
        dataSource = nil
        githubItems = []
        issues = []
        checkoutRows = []
        checkoutSelectedRow = -1
        updateExistsHint()
        issuesTable.reloadData()
        checkoutTable.reloadData()
        updateIssueSectionVisibility()
        updateCreateButton()
    }

    private func selectTab(_ index: Int) {
        currentTab = index
        newBranchContainer.isHidden = (index != 0)
        checkoutContainer.isHidden = (index != 1)
        let field: NSTextField = index == 0 ? branchNameField : filterField
        window?.makeFirstResponder(field)
        updateCreateButton()
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
            self.updateExistsHint()
            self.rebuildCheckoutRows(preserveSelection: true)
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
            self.reloadIssues()
            self.rebuildCheckoutRows(preserveSelection: true)
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

    private func setBaseRowEnabled(_ enabled: Bool) {
        baseBranchPopup.isEnabled = enabled
        baseBranchPopup.alphaValue = enabled ? 1 : 0.4
        baseLabel.alphaValue = enabled ? 1 : 0.4
    }

    // MARK: - Tab 1 Logic

    /// React to typing in the name field: route GitHub references (paste a URL,
    /// or `#123`), otherwise keep the exists-hint and issue association honest.
    private func handleNameChange() {
        let text = branchNameField.stringValue

        if let (kind, number) = GitHubWorkItem.parseURL(text) {
            routeGitHubReference(kind: kind, number: number)
            return
        }
        if let number = hashNumber(in: text),
           let item = githubItems.first(where: { $0.number == number }) {
            route(item)
            return
        }

        // A manual edit that no longer matches the auto-filled name drops the
        // issue association so we don't tag an unrelated branch as issue-derived.
        if let filled = autofilledName, text != filled {
            autofilledName = nil
            issueAssociation = nil
            issuesTable.deselectAll(nil)
        }
        updateExistsHint()
        updateCreateButton()
    }

    /// Route a GitHub reference (from a pasted URL) to the right tab: issues fill
    /// the name field in place; PRs live in "Check Out Existing".
    private func routeGitHubReference(kind: GitHubWorkItem.Kind, number: Int) {
        if let item = githubItems.first(where: { $0.kind == kind && $0.number == number }) {
            route(item)
            return
        }
        switch kind {
        case .issue:
            fillFromIssue(number: number, title: "")
        case .pullRequest:
            switchToCheckout(selecting: number)
        }
    }

    private func route(_ item: GitHubWorkItem) {
        switch item.kind {
        case .issue:
            fillFromIssue(number: item.number, title: item.title)
        case .pullRequest:
            switchToCheckout(selecting: item.number)
        }
    }

    private func fillFromIssue(number: Int, title: String) {
        let name = GitHubWorkItem.issueBranchName(number: number, title: title)
        branchNameField.stringValue = name
        autofilledName = name
        issueAssociation = number
        updateExistsHint()
        updateCreateButton()
    }

    private func switchToCheckout(selecting prNumber: Int) {
        segmentedControl.selectedSegment = 1
        selectTab(1)
        if let idx = checkoutRows.firstIndex(where: {
            if case let .pr(item) = $0 { return item.number == prNumber }
            return false
        }) {
            checkoutSelectedRow = idx
            applyCheckoutSelection()
        }
    }

    /// Show the "already exists" hint and dim the base row when the typed name
    /// exactly matches an existing branch — defining the "can't create" error out
    /// of existence by silently switching to a checkout.
    private func updateExistsHint() {
        let trimmed = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let exists = !trimmed.isEmpty && dataSource?.exactMatch(for: trimmed) != nil
        existsHintLabel.isHidden = !exists
        hintTopConstraint?.constant = exists ? Layout.hintTopGap : 0
        hintHeightConstraint?.constant = exists ? Layout.hintHeight : 0
        setBaseRowEnabled(!exists)
    }

    private func reloadIssues() {
        issues = githubItems.filter { $0.kind == .issue }
        issuesTable.reloadData()
        updateIssueSectionVisibility()
    }

    private func updateIssueSectionVisibility() {
        let hasIssues = !issues.isEmpty
        issueSectionLabel.isHidden = !hasIssues
        issuesScrollView.isHidden = !hasIssues
    }

    /// A bare `#123` reference (trimmed, digits only).
    private func hashNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    // MARK: - Tab 2 Logic

    private func rebuildCheckoutRows(preserveSelection: Bool) {
        let previous: CheckoutRow? = (preserveSelection && checkoutSelectedRow >= 0 && checkoutSelectedRow < checkoutRows.count)
            ? checkoutRows[checkoutSelectedRow] : nil

        checkoutRows = buildCheckoutRows()
        checkoutTable.reloadData()

        if let previous, let idx = checkoutRows.firstIndex(where: { $0.matchesIdentity(previous) }) {
            checkoutSelectedRow = idx
        } else {
            // Empty filter shows no default selection so Enter never fires on an
            // arbitrary first row; a filter that matches nothing clears too.
            checkoutSelectedRow = -1
        }
        applyCheckoutSelection()
    }

    private func buildCheckoutRows() -> [CheckoutRow] {
        guard let ds = dataSource else { return [] }
        let filter = filterField.stringValue
        var rows: [CheckoutRow] = ds
            .checkoutBranches(excluding: excludedBranches, matching: filter)
            .map { .branch($0) }

        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        for item in githubItems where item.kind == .pullRequest {
            let head = item.headRefName ?? ""
            if !head.isEmpty, excludedBranches.contains(head) { continue }
            if !q.isEmpty {
                let haystack = "#\(item.number) \(item.title) \(head)".lowercased()
                guard haystack.contains(q) else { continue }
            }
            rows.append(.pr(item))
        }
        return rows
    }

    private func moveCheckoutSelection(by delta: Int) {
        guard !checkoutRows.isEmpty else { return }
        if checkoutSelectedRow < 0 {
            checkoutSelectedRow = delta >= 0 ? 0 : checkoutRows.count - 1
        } else {
            checkoutSelectedRow = max(0, min(checkoutRows.count - 1, checkoutSelectedRow + delta))
        }
        applyCheckoutSelection()
    }

    private func applyCheckoutSelection() {
        defer { updateCreateButton() }
        guard checkoutSelectedRow >= 0, checkoutSelectedRow < checkoutRows.count else {
            checkoutTable.deselectAll(nil)
            return
        }
        checkoutTable.selectRowIndexes(IndexSet(integer: checkoutSelectedRow), byExtendingSelection: false)
        checkoutTable.scrollRowToVisible(checkoutSelectedRow)
    }

    // MARK: - Create Button

    private func updateCreateButton() {
        let enabled: Bool
        if currentTab == 0 {
            enabled = !branchNameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            enabled = checkoutSelectedRow >= 0 && checkoutSelectedRow < checkoutRows.count
        }
        createButton.isEnabled = enabled
    }

    // MARK: - Confirm

    private func confirm() {
        currentTab == 0 ? confirmNewBranch() : confirmCheckout()
    }

    private func confirmNewBranch() {
        let trimmed = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()

        // The name already names a branch → check it out instead of creating.
        if let match = dataSource?.exactMatch(for: trimmed) {
            let name = match.isRemote ? match.displayName : match.name
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: name,
                isNewBranch: false,
                baseBranch: nil,
                origin: .branch
            ))
            return
        }

        if let number = issueAssociation, branchNameField.stringValue == autofilledName {
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: trimmed,
                isNewBranch: true,
                baseBranch: selectedBaseBranch(),
                origin: .issue(number: number)
            ))
            return
        }

        onCreateWorktree?(WorktreeCreationRequest(
            branchName: trimmed,
            isNewBranch: true,
            baseBranch: selectedBaseBranch(),
            origin: .branch
        ))
    }

    private func confirmCheckout() {
        guard checkoutSelectedRow >= 0, checkoutSelectedRow < checkoutRows.count else { return }
        let row = checkoutRows[checkoutSelectedRow]
        dismiss()
        switch row {
        case let .branch(branch):
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: branch.name,
                isNewBranch: false,
                baseBranch: nil,
                origin: .branch
            ))
        case let .pr(item):
            let head = item.headRefName ?? ""
            onCreateWorktree?(WorktreeCreationRequest(
                branchName: head.isEmpty ? "pr-\(item.number)" : head,
                isNewBranch: false,
                baseBranch: nil,
                origin: .pullRequest(number: item.number, headRef: head)
            ))
        }
    }

    // MARK: - Actions

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        selectTab(sender.selectedSegment)
    }

    @objc private func issueRowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < issues.count else { return }
        let issue = issues[row]
        fillFromIssue(number: issue.number, title: issue.title)
        window?.makeFirstResponder(branchNameField)
    }

    @objc private func checkoutRowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < checkoutRows.count else { return }
        checkoutSelectedRow = row
        applyCheckoutSelection()
        // Keep the field first responder so Enter still confirms via its delegate.
        window?.makeFirstResponder(filterField)
    }

    @objc private func checkoutRowDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0, row < checkoutRows.count else { return }
        checkoutSelectedRow = row
        confirmCheckout()
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
        guard let field = obj.object as? NSTextField else { return }
        if field === branchNameField {
            handleNameChange()
        } else if field === filterField {
            rebuildCheckoutRows(preserveSelection: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === branchNameField {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                confirm()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismiss()
                return true
            case #selector(NSResponder.insertTab(_:)):
                window?.makeFirstResponder(baseBranchPopup)
                return true
            default:
                return false
            }
        }

        if control === filterField {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                moveCheckoutSelection(by: 1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                moveCheckoutSelection(by: -1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                confirm()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismiss()
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Tables

extension WorktreeCreationController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === issuesTable ? issues.count : checkoutRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === issuesTable {
            guard row >= 0, row < issues.count else { return nil }
            return makeIssueCell(issues[row])
        }
        guard row >= 0, row < checkoutRows.count else { return nil }
        switch checkoutRows[row] {
        case let .branch(branch): return makeBranchCell(branch)
        case let .pr(item): return makePRCell(item)
        }
    }

    /// Mirror mouse-driven checkout selection back into the model so Enter and the
    /// create button track it.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as AnyObject === checkoutTable else { return }
        let row = checkoutTable.selectedRow
        if row >= 0, row < checkoutRows.count {
            checkoutSelectedRow = row
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

    private func makeIssueCell(_ item: GitHubWorkItem) -> NSView {
        let cell = NSTableCellView()
        let icon = symbolIcon("smallcircle.filled.circle")
        let number = dimLabel("#\(item.number)", monospacedDigits: true)
        let title = primaryLabel(item.title)

        for view in [icon, number, title] { cell.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            number.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            number.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
