import AppKit
import MoriCore
import MoriGit

// MARK: - Row Model

/// Represents a single row in the branch list — either a section header or a branch.
enum PanelRow {
    case sectionHeader(String) // "LOCAL" or "REMOTE"
    case branch(BranchSuggestion)
}

// MARK: - Inset Selection Row View

/// Custom NSTableRowView that draws an inset rounded selection rect
/// instead of the default full-bleed highlight.
final class InsetSelectionRowView: NSTableRowView {

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let insetRect = NSRect(
            x: 8,
            y: (bounds.height - 30) / 2,
            width: bounds.width - 16,
            height: 30
        )
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)

        // Fill
        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()

        // 1px accent border at 18% opacity
        NSColor.controlAccentColor.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private var isHovering = false

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHovering, !isSelected else { return }
        let insetRect = NSRect(
            x: 8,
            y: (bounds.height - 30) / 2,
            width: bounds.width - 16,
            height: 30
        )
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
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
    private var hoveredRow: Int = -1

    // MARK: - Views

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let tableSeparator = NSBox()
    private let contextLabel = NSTextField(labelWithString: "")
    private let projectLabel = NSTextField(labelWithString: "")

    // Search field background
    private let searchFieldBackground = NSView()

    // Status pill (inside search field area)
    private let statusPillContainer = NSView()
    private let statusPillLabel = NSTextField(labelWithString: "")

    // Footer views
    private let footerContainer = NSView()
    private let footerSeparator = NSBox()
    private let baseCard = NSView()
    private let baseCardLabel = NSTextField(labelWithString: "")
    private let baseCardValue = NSTextField(labelWithString: "")
    private let templateCard = NSView()
    private let templateCardLabel = NSTextField(labelWithString: "")
    private let templateCardValue = NSTextField(labelWithString: "")
    private let pathCard = NSView()
    private let pathCardLabel = NSTextField(labelWithString: "")
    private let pathCardValue = NSTextField(labelWithString: "")

    // Hidden controls for tab navigation (base branch editing + template selection)
    private let baseBranchField = NSTextField()
    private let templatePopup = NSPopUpButton()

    // MARK: - Layout Constants

    private enum Layout {
        static let panelWidth: CGFloat = 616
        static let panelOuterPaddingH: CGFloat = 12
        static let panelTopPadding: CGFloat = 12
        static let panelBottomPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 14

        static let contextRowHeight: CGFloat = 18
        static let contextGap: CGFloat = 8

        static let searchFieldHeight: CGFloat = 42
        static let searchFieldCornerRadius: CGFloat = 10
        static let searchFontSize: CGFloat = 16
        static let placeholderFontSize: CGFloat = 15

        static let pillWidth: CGFloat = 56
        static let pillHeight: CGFloat = 20
        static let pillRadius: CGFloat = 6
        static let pillFontSize: CGFloat = 10

        static let listGap: CGFloat = 8
        static let sectionHeaderHeight: CGFloat = 20
        static let sectionHeaderLeading: CGFloat = 16
        static let sectionHeaderFontSize: CGFloat = 10

        static let rowHeight: CGFloat = 34
        static let rowContentPaddingH: CGFloat = 12
        static let cellIconSize: CGFloat = 14
        static let cellIconGap: CGFloat = 8
        static let branchFontSize: CGFloat = 13

        static let headPillWidth: CGFloat = 38
        static let headPillHeight: CGFloat = 18
        static let headPillRadius: CGFloat = 6

        static let remoteCapsuleHeight: CGFloat = 18
        static let remoteCapsuleMinWidth: CGFloat = 42
        static let remoteCapsulePaddingH: CGFloat = 8
        static let remoteCapsuleRadius: CGFloat = 6

        static let openPillWidth: CGFloat = 44
        static let openPillHeight: CGFloat = 18
        static let openPillRadius: CGFloat = 6

        static let commitAgeLaneWidth: CGFloat = 60
        static let commitAgeFontSize: CGFloat = 11

        static let accentRailWidth: CGFloat = 2

        static let maxVisibleRows: Int = 10
        static let panelTopOffset: CGFloat = 80

        static let footerHeight: CGFloat = 92
        static let footerPaddingTop: CGFloat = 10
        static let footerPaddingH: CGFloat = 12
        static let footerPaddingBottom: CGFloat = 10
        static let cardHeight: CGFloat = 36
        static let cardRadius: CGFloat = 10
        static let cardPaddingH: CGFloat = 10
        static let cardPaddingTop: CGFloat = 6
        static let cardGap: CGFloat = 8
        static let cardLabelFontSize: CGFloat = 10
        static let cardValueFontSize: CGFloat = 12

        static let baseCardWidth: CGFloat = 252
        static let templateCardWidth: CGFloat = 332

        static let pathCardHeight: CGFloat = 28
        static let pathCardRadius: CGFloat = 8
        static let pathLabelFontSize: CGFloat = 10
        static let pathValueFontSize: CGFloat = 11
    }

    // MARK: - Init

    init() {
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
        updateStatusPill()
        updateFooter()

        // Update context row
        projectLabel.stringValue = projectName

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

        setupContextRow()
        setupSearchField()
        setupTableView()
        setupFooter()
        setupHiddenControls()
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

    private func setupContextRow() {
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        contextLabel.stringValue = String.localized("NEW WORKTREE")
        contextLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.isEditable = false
        contextLabel.isBordered = false
        contextLabel.backgroundColor = .clear
        containerView.addSubview(contextLabel)

        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        projectLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        projectLabel.textColor = .tertiaryLabelColor
        projectLabel.alignment = .right
        projectLabel.isEditable = false
        projectLabel.isBordered = false
        projectLabel.backgroundColor = .clear
        containerView.addSubview(projectLabel)
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

        // Search field background container
        searchFieldBackground.translatesAutoresizingMaskIntoConstraints = false
        searchFieldBackground.wantsLayer = true
        searchFieldBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        searchFieldBackground.layer?.cornerRadius = Layout.searchFieldCornerRadius
        containerView.addSubview(searchFieldBackground)
        containerView.addSubview(searchField)

        // Placeholder font styling
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: Layout.placeholderFontSize, weight: .regular),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        searchField.placeholderAttributedString = NSAttributedString(
            string: .localized("Branch name..."),
            attributes: placeholderAttrs
        )

        // Status pill overlay
        statusPillContainer.translatesAutoresizingMaskIntoConstraints = false
        statusPillContainer.wantsLayer = true
        statusPillContainer.layer?.cornerRadius = Layout.pillRadius
        statusPillContainer.isHidden = true
        containerView.addSubview(statusPillContainer)

        statusPillLabel.translatesAutoresizingMaskIntoConstraints = false
        statusPillLabel.font = .systemFont(ofSize: Layout.pillFontSize, weight: .semibold)
        statusPillLabel.alignment = .center
        statusPillLabel.isEditable = false
        statusPillLabel.isBordered = false
        statusPillLabel.backgroundColor = .clear
        statusPillContainer.addSubview(statusPillLabel)

        NSLayoutConstraint.activate([
            statusPillLabel.centerXAnchor.constraint(equalTo: statusPillContainer.centerXAnchor),
            statusPillLabel.centerYAnchor.constraint(equalTo: statusPillContainer.centerYAnchor),
        ])
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branches"))
        column.title = ""
        column.width = Layout.panelWidth - Layout.panelOuterPaddingH * 2
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = Layout.rowHeight
        tableView.selectionHighlightStyle = .none // We draw our own
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.backgroundColor = .windowBackgroundColor
        tableView.gridStyleMask = [] // No grid lines

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
        footerContainer.wantsLayer = true
        footerContainer.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        containerView.addSubview(footerContainer)

        // Top divider
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.boxType = .custom
        footerSeparator.fillColor = .separatorColor
        footerContainer.addSubview(footerSeparator)

        // Base card
        configureCard(baseCard, radius: Layout.cardRadius)
        footerContainer.addSubview(baseCard)

        baseCardLabel.translatesAutoresizingMaskIntoConstraints = false
        baseCardLabel.stringValue = "BASE"
        baseCardLabel.font = .systemFont(ofSize: Layout.cardLabelFontSize, weight: .semibold)
        baseCardLabel.textColor = .tertiaryLabelColor
        baseCardLabel.isEditable = false
        baseCardLabel.isBordered = false
        baseCardLabel.backgroundColor = .clear
        baseCard.addSubview(baseCardLabel)

        baseCardValue.translatesAutoresizingMaskIntoConstraints = false
        baseCardValue.font = .monospacedSystemFont(ofSize: Layout.cardValueFontSize, weight: .medium)
        baseCardValue.textColor = .labelColor
        baseCardValue.isEditable = false
        baseCardValue.isBordered = false
        baseCardValue.backgroundColor = .clear
        baseCardValue.lineBreakMode = .byTruncatingTail
        baseCard.addSubview(baseCardValue)

        // Template card
        configureCard(templateCard, radius: Layout.cardRadius)
        footerContainer.addSubview(templateCard)

        templateCardLabel.translatesAutoresizingMaskIntoConstraints = false
        templateCardLabel.stringValue = "TEMPLATE"
        templateCardLabel.font = .systemFont(ofSize: Layout.cardLabelFontSize, weight: .semibold)
        templateCardLabel.textColor = .tertiaryLabelColor
        templateCardLabel.isEditable = false
        templateCardLabel.isBordered = false
        templateCardLabel.backgroundColor = .clear
        templateCard.addSubview(templateCardLabel)

        templateCardValue.translatesAutoresizingMaskIntoConstraints = false
        templateCardValue.font = .systemFont(ofSize: Layout.cardValueFontSize, weight: .regular)
        templateCardValue.textColor = .labelColor
        templateCardValue.isEditable = false
        templateCardValue.isBordered = false
        templateCardValue.backgroundColor = .clear
        templateCard.addSubview(templateCardValue)

        // Path card
        configureCard(pathCard, radius: Layout.pathCardRadius)
        footerContainer.addSubview(pathCard)

        pathCardLabel.translatesAutoresizingMaskIntoConstraints = false
        pathCardLabel.stringValue = "PATH"
        pathCardLabel.font = .systemFont(ofSize: Layout.pathLabelFontSize, weight: .semibold)
        pathCardLabel.textColor = .tertiaryLabelColor
        pathCardLabel.isEditable = false
        pathCardLabel.isBordered = false
        pathCardLabel.backgroundColor = .clear
        pathCard.addSubview(pathCardLabel)

        pathCardValue.translatesAutoresizingMaskIntoConstraints = false
        pathCardValue.font = .monospacedSystemFont(ofSize: Layout.pathValueFontSize, weight: .regular)
        pathCardValue.textColor = .secondaryLabelColor
        pathCardValue.isEditable = false
        pathCardValue.isBordered = false
        pathCardValue.backgroundColor = .clear
        pathCardValue.lineBreakMode = .byTruncatingMiddle
        pathCard.addSubview(pathCardValue)

        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),

            // Base card
            baseCard.topAnchor.constraint(equalTo: footerSeparator.bottomAnchor, constant: Layout.footerPaddingTop),
            baseCard.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.footerPaddingH),
            baseCard.widthAnchor.constraint(equalToConstant: Layout.baseCardWidth),
            baseCard.heightAnchor.constraint(equalToConstant: Layout.cardHeight),

            baseCardLabel.topAnchor.constraint(equalTo: baseCard.topAnchor, constant: Layout.cardPaddingTop),
            baseCardLabel.leadingAnchor.constraint(equalTo: baseCard.leadingAnchor, constant: Layout.cardPaddingH),

            baseCardValue.leadingAnchor.constraint(equalTo: baseCard.leadingAnchor, constant: Layout.cardPaddingH),
            baseCardValue.bottomAnchor.constraint(equalTo: baseCard.bottomAnchor, constant: -4),
            baseCardValue.trailingAnchor.constraint(lessThanOrEqualTo: baseCard.trailingAnchor, constant: -Layout.cardPaddingH),

            // Template card
            templateCard.topAnchor.constraint(equalTo: baseCard.topAnchor),
            templateCard.leadingAnchor.constraint(equalTo: baseCard.trailingAnchor, constant: Layout.cardGap),
            templateCard.widthAnchor.constraint(equalToConstant: Layout.templateCardWidth),
            templateCard.heightAnchor.constraint(equalToConstant: Layout.cardHeight),

            templateCardLabel.topAnchor.constraint(equalTo: templateCard.topAnchor, constant: Layout.cardPaddingTop),
            templateCardLabel.leadingAnchor.constraint(equalTo: templateCard.leadingAnchor, constant: Layout.cardPaddingH),

            templateCardValue.leadingAnchor.constraint(equalTo: templateCard.leadingAnchor, constant: Layout.cardPaddingH),
            templateCardValue.bottomAnchor.constraint(equalTo: templateCard.bottomAnchor, constant: -4),
            templateCardValue.trailingAnchor.constraint(lessThanOrEqualTo: templateCard.trailingAnchor, constant: -Layout.cardPaddingH),

            // Path card
            pathCard.topAnchor.constraint(equalTo: baseCard.bottomAnchor, constant: Layout.cardGap),
            pathCard.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: Layout.footerPaddingH),
            pathCard.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -Layout.footerPaddingH),
            pathCard.heightAnchor.constraint(equalToConstant: Layout.pathCardHeight),

            pathCardLabel.centerYAnchor.constraint(equalTo: pathCard.centerYAnchor),
            pathCardLabel.leadingAnchor.constraint(equalTo: pathCard.leadingAnchor, constant: Layout.cardPaddingH),

            pathCardValue.centerYAnchor.constraint(equalTo: pathCard.centerYAnchor),
            pathCardValue.leadingAnchor.constraint(equalTo: pathCardLabel.trailingAnchor, constant: 6),
            pathCardValue.trailingAnchor.constraint(lessThanOrEqualTo: pathCard.trailingAnchor, constant: -Layout.cardPaddingH),

            footerContainer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
        ])
    }

    private func setupHiddenControls() {
        // baseBranchField and templatePopup are kept off-screen for Tab navigation
        baseBranchField.translatesAutoresizingMaskIntoConstraints = false
        baseBranchField.placeholderString = "main"
        baseBranchField.font = .systemFont(ofSize: 11)
        baseBranchField.isBordered = true
        baseBranchField.bezelStyle = .roundedBezel
        baseBranchField.focusRingType = .none
        baseBranchField.delegate = self
        baseBranchField.isHidden = true
        containerView.addSubview(baseBranchField)

        templatePopup.translatesAutoresizingMaskIntoConstraints = false
        templatePopup.font = .systemFont(ofSize: 11)
        templatePopup.removeAllItems()
        for template in TemplateRegistry.all {
            templatePopup.addItem(withTitle: template.name.capitalized)
        }
        templatePopup.controlSize = .small
        templatePopup.target = self
        templatePopup.action = #selector(templateChanged(_:))
        templatePopup.isHidden = true
        containerView.addSubview(templatePopup)
    }

    private func configureCard(_ card: NSView, radius: CGFloat) {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = radius
    }

    private func layoutViews() {
        tableSeparator.translatesAutoresizingMaskIntoConstraints = false
        tableSeparator.boxType = .custom
        tableSeparator.fillColor = .separatorColor
        containerView.addSubview(tableSeparator)

        let searchBg = searchFieldBackground

        NSLayoutConstraint.activate([
            // Context row
            contextLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Layout.panelTopPadding),
            contextLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelOuterPaddingH),
            contextLabel.heightAnchor.constraint(equalToConstant: Layout.contextRowHeight),

            projectLabel.centerYAnchor.constraint(equalTo: contextLabel.centerYAnchor),
            projectLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelOuterPaddingH),

            // Search field background
            searchBg.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: Layout.contextGap),
            searchBg.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Layout.panelOuterPaddingH),
            searchBg.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Layout.panelOuterPaddingH),
            searchBg.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),

            // Search field (inside background)
            searchField.leadingAnchor.constraint(equalTo: searchBg.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: statusPillContainer.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchBg.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight - 4),

            // Status pill (trailing inside search bg)
            statusPillContainer.trailingAnchor.constraint(equalTo: searchBg.trailingAnchor, constant: -8),
            statusPillContainer.centerYAnchor.constraint(equalTo: searchBg.centerYAnchor),
            statusPillContainer.widthAnchor.constraint(equalToConstant: Layout.pillWidth),
            statusPillContainer.heightAnchor.constraint(equalToConstant: Layout.pillHeight),

            // Separator
            tableSeparator.topAnchor.constraint(equalTo: searchBg.bottomAnchor, constant: Layout.listGap),
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
        let topArea = Layout.panelTopPadding + Layout.contextRowHeight + Layout.contextGap
            + Layout.searchFieldHeight + Layout.listGap + 1 // separator
        let rowCount = rows.isEmpty ? 1 : min(rows.count, Layout.maxVisibleRows)
        let tableHeight = CGFloat(rowCount) * Layout.rowHeight
        return topArea + tableHeight + Layout.footerHeight
    }

    // MARK: - Results

    private func updateResults() {
        let query = searchField.stringValue
        let grouped = dataSource?.filteredGrouped(query: query)
            ?? (local: [], remote: [])

        // Build flat rows with section headers only when both groups present
        var newRows: [PanelRow] = []
        let hasLocal = !grouped.local.isEmpty
        let hasRemote = !grouped.remote.isEmpty
        let showHeaders = hasLocal && hasRemote

        if showHeaders {
            newRows.append(.sectionHeader("LOCAL"))
        }
        for s in grouped.local {
            newRows.append(.branch(s))
        }
        if showHeaders {
            newRows.append(.sectionHeader("REMOTE"))
        }
        for s in grouped.remote {
            newRows.append(.branch(s))
        }

        rows = newRows
        suggestions = grouped.local + grouped.remote

        // Select first branch row
        selectedIndex = rows.firstIndex(where: { if case .branch = $0 { return true }; return false }) ?? -1

        tableView.reloadData()

        if selectedIndex >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }

        updateStatusPill()
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

    // MARK: - Status & Footer

    private func updateStatusPill() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            statusPillContainer.isHidden = true
            return
        }

        statusPillContainer.isHidden = false

        if dataSource?.exactMatch(for: query) != nil {
            // EXISTS pill
            statusPillLabel.stringValue = "EXISTS"
            statusPillLabel.textColor = .controlAccentColor
            statusPillContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        } else {
            // NEW pill
            statusPillLabel.stringValue = "NEW"
            statusPillLabel.textColor = .systemGreen
            statusPillContainer.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
        }
    }

    private func updateFooter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let isExisting = query.isEmpty ? false : dataSource?.exactMatch(for: query) != nil
        let template = selectedTemplate()

        // Base card
        if isExisting {
            baseCard.alphaValue = 0.55
            baseCardValue.stringValue = String.localized("Not used")
        } else {
            baseCard.alphaValue = 1.0
            let base = baseBranchField.stringValue.isEmpty
                ? (dataSource?.defaultBaseBranch ?? "main")
                : baseBranchField.stringValue
            baseCardValue.stringValue = base
        }

        // Template card
        templateCardValue.stringValue = template.name.capitalized

        // Path card
        if query.isEmpty {
            pathCardValue.stringValue = ""
        } else {
            let branchForPath: String
            if let match = dataSource?.exactMatch(for: query) {
                branchForPath = match.isRemote ? match.displayName : match.name
            } else {
                branchForPath = query
            }
            pathCardValue.stringValue = WorktreeCreationDataSource.previewPath(
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

    // MARK: - Pill Factory

    /// Creates a reusable pill view with rounded rect background at 12% opacity + centered label.
    private static func makePill(
        text: String,
        textColor: NSColor,
        fillColor: NSColor,
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat,
        fontSize: CGFloat = 10,
        weight: NSFont.Weight = .semibold
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = fillColor.withAlphaComponent(0.12).cgColor
        container.layer?.cornerRadius = radius

        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: fontSize, weight: weight)
        label.textColor = textColor
        label.alignment = .center
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: height),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    /// Creates a remote capsule (e.g., "origin") with border.
    private static func makeRemoteCapsule(text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = Layout.remoteCapsuleRadius

        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Layout.remoteCapsuleHeight),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.remoteCapsuleMinWidth),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.remoteCapsulePaddingH),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.remoteCapsulePaddingH),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        switch rows[row] {
        case .sectionHeader:
            return NSTableRowView()
        case .branch:
            let rowView = InsetSelectionRowView()
            rowView.selectionHighlightStyle = .none
            return rowView
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
        // Refresh row views for selection styling
        tableView.enumerateAvailableRowViews { rowView, rowIdx in
            if let inset = rowView as? InsetSelectionRowView {
                inset.isSelected = (rowIdx == selectedIndex)
                inset.needsDisplay = true
            }
        }
    }

    // MARK: - Section Header

    private func makeSectionHeaderView(title: String) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Layout.sectionHeaderFontSize, weight: .semibold)
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
        let cell = NSView()
        cell.wantsLayer = true

        let leadingAnchor = cell.leadingAnchor
        let leadingConstant = Layout.rowContentPaddingH

        // HEAD accent rail (2px leading edge)
        if info.isHead {
            let rail = NSView()
            rail.translatesAutoresizingMaskIntoConstraints = false
            rail.wantsLayer = true
            rail.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            cell.addSubview(rail)
            NSLayoutConstraint.activate([
                rail.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                rail.topAnchor.constraint(equalTo: cell.topAnchor),
                rail.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                rail.widthAnchor.constraint(equalToConstant: Layout.accentRailWidth),
            ])
        }

        // Icon
        let icon = info.isRemote ? "cloud" : "arrow.branch"
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        imageView.imageScaling = .scaleProportionallyDown
        // In-use: mute icon to .secondaryLabelColor; otherwise normal
        imageView.contentTintColor = suggestion.inUse ? .secondaryLabelColor : .secondaryLabelColor
        cell.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingConstant),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.cellIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.cellIconSize),
        ])

        // Branch name
        let displayName = info.isRemote ? info.displayName : info.name
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        if info.isHead {
            nameLabel.font = .monospacedSystemFont(ofSize: Layout.branchFontSize, weight: .semibold)
        } else {
            nameLabel.font = .monospacedSystemFont(ofSize: Layout.branchFontSize, weight: .regular)
        }
        nameLabel.textColor = info.isRemote ? .secondaryLabelColor : .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        cell.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: Layout.cellIconGap),
            nameLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Trailing items are laid out right-to-left
        var trailingAnchorRef = cell.trailingAnchor
        var trailingConstant: CGFloat = -Layout.rowContentPaddingH

        // OPEN pill (in-use)
        if suggestion.inUse {
            let openPill = Self.makePill(
                text: "OPEN",
                textColor: .systemOrange,
                fillColor: .systemOrange,
                width: Layout.openPillWidth,
                height: Layout.openPillHeight,
                radius: Layout.openPillRadius
            )
            cell.addSubview(openPill)
            NSLayoutConstraint.activate([
                openPill.trailingAnchor.constraint(equalTo: trailingAnchorRef, constant: trailingConstant),
                openPill.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            trailingAnchorRef = openPill.leadingAnchor
            trailingConstant = -6
        }

        // Commit age (right-aligned 60px lane)
        if let commitDate = info.commitDate {
            let timeLabel = NSTextField(labelWithString: relativeTimeString(from: commitDate))
            timeLabel.translatesAutoresizingMaskIntoConstraints = false
            timeLabel.font = .monospacedSystemFont(ofSize: Layout.commitAgeFontSize, weight: .regular)
            timeLabel.textColor = .tertiaryLabelColor
            timeLabel.alignment = .right
            cell.addSubview(timeLabel)
            NSLayoutConstraint.activate([
                timeLabel.trailingAnchor.constraint(equalTo: trailingAnchorRef, constant: trailingConstant),
                timeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                timeLabel.widthAnchor.constraint(equalToConstant: Layout.commitAgeLaneWidth),
            ])
            trailingAnchorRef = timeLabel.leadingAnchor
            trailingConstant = -6
        }

        // HEAD pill
        if info.isHead {
            let headPill = Self.makePill(
                text: "HEAD",
                textColor: .controlAccentColor,
                fillColor: .controlAccentColor,
                width: Layout.headPillWidth,
                height: Layout.headPillHeight,
                radius: Layout.headPillRadius
            )
            cell.addSubview(headPill)
            NSLayoutConstraint.activate([
                headPill.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
                headPill.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            // Don't let head pill overlap trailing items
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorRef, constant: trailingConstant - Layout.headPillWidth - 12).isActive = true
        }

        // Remote capsule (origin/upstream)
        if info.isRemote, let remoteName = info.remoteName {
            let capsule = Self.makeRemoteCapsule(text: remoteName)
            cell.addSubview(capsule)
            NSLayoutConstraint.activate([
                capsule.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
                capsule.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorRef, constant: trailingConstant - Layout.remoteCapsuleMinWidth - 12).isActive = true
        } else if !info.isHead {
            // Just constrain name label to not overlap trailing
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorRef, constant: trailingConstant).isActive = true
        }

        return cell
    }
}
