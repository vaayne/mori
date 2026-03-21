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

    // MARK: - Callbacks

    /// Called when the user confirms worktree creation.
    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?

    /// Called to fetch branches asynchronously.
    var fetchBranches: ((_ repoPath: String) async throws -> [GitBranchInfo])?

    /// Called when the user switches projects in the popup.
    var onProjectChanged: ((UUID) -> Void)?

    // MARK: - State

    private var dataSource: WorktreeCreationDataSource?
    private var projects: [Project] = []
    private var selectedProjectId: UUID?
    private var repoPath: String = ""
    private var fetchGeneration: Int = 0
    nonisolated(unsafe) private var localEventMonitor: Any?

    // MARK: - Views

    private let branchNameField = NSTextField()
    private let toolbarContainer = NSView()
    private let projectPopup = NSPopUpButton()
    private let baseBranchPopup = NSPopUpButton()
    private let createHintLabel = NSTextField(labelWithString: "")
    private let containerView = NSView()

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
        existingBranches: Set<String>,
        themeInfo: GhosttyThemeInfo
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath

        // Reset state
        branchNameField.stringValue = ""
        dataSource = nil

        // Apply theme
        applyTheme(themeInfo)

        // Populate project popup
        populateProjectPopup()

        // Reset base branch popup
        baseBranchPopup.removeAllItems()
        baseBranchPopup.addItem(withTitle: "\u{2387} main")
        baseBranchPopup.isEnabled = true

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
            } catch {
                guard self.fetchGeneration == currentGeneration else { return }
                self.dataSource = WorktreeCreationDataSource(
                    branches: [],
                    existingBranchNames: existingBranches
                )
            }
        }
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
            toolbarContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Layout.bottomPadding),
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
            baseBranchPopup.addItem(withTitle: "\u{2387} main")
        } else {
            for name in branchNames {
                baseBranchPopup.addItem(withTitle: "\u{2387} \(name)")
            }
            let defaultBranch = ds.defaultBaseBranch
            if let idx = branchNames.firstIndex(of: defaultBranch) {
                baseBranchPopup.selectItem(at: idx)
            }
        }
    }

    // MARK: - Confirm

    private func confirmInput() {
        let branchText = branchNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branchText.isEmpty else { return }

        let template = TemplateRegistry.basic

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
        // No-op — base branch selection is read at confirm time
    }
}

// MARK: - NSTextFieldDelegate

extension WorktreeCreationController: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === branchNameField else { return false }

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
