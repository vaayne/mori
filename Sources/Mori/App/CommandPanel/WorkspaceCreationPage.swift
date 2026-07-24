import AppKit
import MoriCore
import MoriGit

/// Command-panel page answering one question: which branch will the new
/// workspace check out? All picker semantics live in `WorkspacePickerModel`
/// (MoriCore, tested); this page owns the async fetches, the footer accessory
/// (project switcher, base branch, confirm hint), and the mapping from
/// semantic rows to display rows.
@MainActor
final class WorkspaceCreationPage: CommandPanelPage {

    // MARK: - Callbacks (wired by AppDelegate, mirroring the old panel)

    var onCreateWorktree: ((WorktreeCreationRequest) -> Void)?
    var fetchBranches: ((_ projectId: UUID, _ repoPath: String) async throws -> [GitBranchInfo])?
    /// Returns `[]` for remote/SSH projects (gh is local-only).
    var fetchGitHubItems: ((_ projectId: UUID, _ repoPath: String) async -> [GitHubWorkItem])?
    var onProjectChanged: ((UUID) -> Void)?

    // MARK: - State

    private var projects: [Project] = []
    private var selectedProjectId: UUID?
    private var repoPath: String = ""
    private var excludedBranches: Set<String> = []

    private var branches: [PickerBranch] = []
    private var githubItems: [GitHubWorkItem] = []
    private var model = WorkspacePickerModel()
    private var modelRows: [WorkspacePickerModel.Row] = []
    private var lastQuery: String = ""

    private var branchGeneration = FetchGeneration()
    private var githubGeneration = FetchGeneration()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// SF Symbol beats a text glyph in popup titles: the ⎇ character renders
    /// inconsistently across fonts, and a menu-item image tints with appearance.
    private static let branchMenuImage: NSImage? = NSImage(
        systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))

    // MARK: - Footer views

    private let footer = NSView()
    private let projectPopup = NSPopUpButton()
    private let baseLabel = NSTextField(labelWithString: "")
    private let baseBranchPopup = NSPopUpButton()
    private let confirmHintButton = NSButton()
    private var confirmEnabled = false

    init() {
        buildFooter()
    }

    // MARK: - Configuration (AppDelegate)

    /// Set the project context before the page is opened, pushed, or refreshed.
    func configure(
        projects: [Project],
        selectedProjectId: UUID,
        repoPath: String,
        excludedBranches: Set<String>
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.repoPath = repoPath
        self.excludedBranches = excludedBranches
        populateProjectPopup()
    }

    /// Re-fetch data in place after the project changed while the page is
    /// showing — no container reset, the typed query stays.
    func refreshData() {
        branches = []
        githubItems = []
        rebuildModel()
        startFetches()
    }

    // MARK: - CommandPanelPage

    var placeholder: String { .localized("Branch name, or search branches, PRs, issues") }
    var breadcrumbTitle: String? { .localized("New Workspace") }
    var heightPolicy: CommandPanelHeightPolicy { .fixed(300) }
    var footerView: NSView? { footer }
    var onRowsChanged: (() -> Void)?
    var onConfirmRequested: (() -> Void)?

    func activate() {
        branches = []
        githubItems = []
        rebuildModel()
        startFetches()
    }

    func deactivate() {
        branchGeneration.invalidate()
        githubGeneration.invalidate()
    }

    func normalizeQuery(_ query: String) -> String? {
        model.normalizedQuery(for: query)
    }

    func rows(for query: String) -> [CommandPanelRow] {
        lastQuery = query
        modelRows = model.rows(for: query)
        return modelRows.map(displayRow(for:))
    }

    func defaultSelectionId(for query: String) -> String? {
        model.defaultSelectionId(for: query, in: modelRows)
    }

    func selectionDidChange(rowId: String?) {
        let row = modelRow(id: rowId)
        setBaseRowVisible(row?.createsNewBranch ?? false)
        setConfirmEnabled(row?.isSelectable ?? false)
    }

    func handleTab() -> Bool {
        guard !baseBranchPopup.isHidden else { return false }
        baseBranchPopup.window?.makeFirstResponder(baseBranchPopup)
        return true
    }

    func confirm(rowId: String) -> CommandPanelConfirmResult {
        guard let row = modelRow(id: rowId), row.isSelectable,
              let projectId = selectedProjectId else { return .stay }
        let base = selectedBaseBranch()
        let create = onCreateWorktree

        switch row {
        case .branchesHeader, .pullRequestsHeader, .issuesHeader,
             .unknownPRHint, .branchAlreadyOpenHint:
            return .stay
        case .create(let name):
            return .dismiss(then: {
                create?(WorktreeCreationRequest(
                    projectId: projectId, branchName: name, isNewBranch: true,
                    baseBranch: base, origin: .branch
                ))
            })
        case .branch(let branch):
            return .dismiss(then: {
                create?(WorktreeCreationRequest(
                    projectId: projectId,
                    branchName: branch.isRemote ? branch.displayName : branch.name,
                    isNewBranch: false, baseBranch: nil, origin: .branch
                ))
            })
        case .pr(let item):
            // branchName is ignored for a PR origin — the manager takes the
            // branch from headRef (and rejects an empty one).
            let head = item.headRefName ?? ""
            return .dismiss(then: {
                create?(WorktreeCreationRequest(
                    projectId: projectId, branchName: head, isNewBranch: false,
                    baseBranch: nil, origin: .pullRequest(number: item.number, headRef: head)
                ))
            })
        case .issue(let item):
            return .dismiss(then: {
                create?(WorktreeCreationRequest(
                    projectId: projectId,
                    branchName: GitHubWorkItem.issueBranchName(number: item.number, title: item.title),
                    isNewBranch: true, baseBranch: base,
                    origin: .issue(number: item.number)
                ))
            })
        }
    }

    // MARK: - Row mapping

    private func modelRow(id: String?) -> WorkspacePickerModel.Row? {
        guard let id else { return nil }
        return modelRows.first(where: { $0.id == id })
    }

    private func displayRow(for row: WorkspacePickerModel.Row) -> CommandPanelRow {
        switch row {
        case .branchesHeader:
            return .sectionHeader(id: row.id, title: .localized("Branches"))
        case .pullRequestsHeader:
            return .sectionHeader(id: row.id, title: .localized("Pull Requests"))
        case .issuesHeader:
            return .sectionHeader(id: row.id, title: .localized("Issues"))
        case .unknownPRHint(let number):
            return .hint(id: row.id, title: String(
                format: .localized("PR #%d isn’t among the open pull requests — it may be closed, merged, or beyond the fetched list."),
                number
            ))
        case .branchAlreadyOpenHint(let name):
            return .hint(id: row.id, title: String(
                format: .localized("“%@” is already open as a workspace."),
                name
            ))
        case .create(let name):
            return .item(
                id: row.id, iconName: "plus.circle",
                title: String(format: .localized("Create branch “%@”"), name)
            )
        case .branch(let branch):
            let date = branch.commitDate.map {
                Self.relativeDateFormatter.localizedString(for: $0, relativeTo: Date())
            }
            return .item(
                id: row.id, iconName: "arrow.triangle.branch",
                title: branch.name, trailingText: date
            )
        case .pr(let item):
            return .item(
                id: row.id, iconName: "arrow.triangle.pull",
                title: item.title, subtitle: "#\(item.number)",
                trailingText: item.headRefName
            )
        case .issue(let item):
            // Trailing shows the branch the row will create, so selecting an
            // issue is not a surprise.
            return .item(
                id: row.id, iconName: "smallcircle.filled.circle",
                title: item.title, subtitle: "#\(item.number)",
                trailingText: GitHubWorkItem.issueBranchName(number: item.number, title: item.title)
            )
        }
    }

    // MARK: - Fetching

    private func startFetches() {
        guard let projectId = selectedProjectId else { return }
        let repoPath = repoPath

        let branchToken = branchGeneration.begin()
        Task { [weak self] in
            guard let self else { return }
            var fetched: [GitBranchInfo] = []
            do {
                fetched = try await self.fetchBranches?(projectId, repoPath) ?? []
            } catch {
                fetched = []
            }
            guard self.branchGeneration.isCurrent(branchToken) else { return }
            self.branches = fetched.map(PickerBranch.init)
            self.rebuildModel()
        }

        let githubToken = githubGeneration.begin()
        Task { [weak self] in
            guard let self else { return }
            let items = await self.fetchGitHubItems?(projectId, repoPath) ?? []
            guard self.githubGeneration.isCurrent(githubToken) else { return }
            self.githubItems = items
            self.rebuildModel()
        }
    }

    private func rebuildModel() {
        model = WorkspacePickerModel(
            branches: branches,
            githubItems: githubItems,
            excludedBranches: excludedBranches
        )
        populateBaseBranchPopup()
        onRowsChanged?()
    }

    // MARK: - Footer

    private func buildFooter() {
        projectPopup.translatesAutoresizingMaskIntoConstraints = false
        projectPopup.controlSize = .small
        projectPopup.font = .systemFont(ofSize: 12)
        projectPopup.target = self
        projectPopup.action = #selector(projectChanged(_:))
        (projectPopup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        projectPopup.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        footer.addSubview(projectPopup)

        baseLabel.translatesAutoresizingMaskIntoConstraints = false
        baseLabel.stringValue = .localized("Base")
        baseLabel.font = .systemFont(ofSize: 12)
        baseLabel.textColor = .secondaryLabelColor
        baseLabel.setContentHuggingPriority(.required, for: .horizontal)
        footer.addSubview(baseLabel)

        baseBranchPopup.translatesAutoresizingMaskIntoConstraints = false
        baseBranchPopup.controlSize = .small
        baseBranchPopup.font = .systemFont(ofSize: 12)
        (baseBranchPopup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        baseBranchPopup.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        footer.addSubview(baseBranchPopup)

        // A hint, not a default button: no keyEquivalent, so Enter stays on the
        // field-delegate path instead of being intercepted before the field editor.
        confirmHintButton.translatesAutoresizingMaskIntoConstraints = false
        confirmHintButton.isBordered = false
        confirmHintButton.setButtonType(.momentaryChange)
        confirmHintButton.target = self
        confirmHintButton.action = #selector(confirmHintClicked(_:))
        confirmHintButton.setContentHuggingPriority(.required, for: .horizontal)
        confirmHintButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        footer.addSubview(confirmHintButton)

        NSLayoutConstraint.activate([
            projectPopup.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            projectPopup.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            projectPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 180),

            confirmHintButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            confirmHintButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            baseBranchPopup.trailingAnchor.constraint(equalTo: confirmHintButton.leadingAnchor, constant: -14),
            baseBranchPopup.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            baseBranchPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            baseBranchPopup.leadingAnchor.constraint(greaterThanOrEqualTo: projectPopup.trailingAnchor, constant: 12),

            baseLabel.trailingAnchor.constraint(equalTo: baseBranchPopup.leadingAnchor, constant: -6),
            baseLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        setBaseRowVisible(false)
        setConfirmEnabled(false)
        resetBaseBranchPopup()
    }

    private func setBaseRowVisible(_ visible: Bool) {
        baseLabel.isHidden = !visible
        baseBranchPopup.isHidden = !visible
    }

    private func setConfirmEnabled(_ enabled: Bool) {
        confirmEnabled = enabled
        confirmHintButton.isEnabled = enabled
        let color: NSColor = enabled ? .controlAccentColor : .tertiaryLabelColor
        confirmHintButton.attributedTitle = NSAttributedString(
            string: "\(String.localized("Create Workspace")) ↩",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]
        )
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
        addBaseBranchItem(model.defaultBaseBranch)
    }

    private func populateBaseBranchPopup() {
        baseBranchPopup.removeAllItems()
        let names = model.localBranchNames
        if names.isEmpty {
            addBaseBranchItem(model.defaultBaseBranch)
        } else {
            for name in names {
                addBaseBranchItem(name)
            }
            if let idx = names.firstIndex(of: model.defaultBaseBranch) {
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
        return model.defaultBaseBranch
    }

    // MARK: - Actions

    @objc private func confirmHintClicked(_ sender: NSButton) {
        guard confirmEnabled else { return }
        onConfirmRequested?()
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

private extension PickerBranch {
    init(_ info: GitBranchInfo) {
        self.init(
            name: info.name,
            displayName: info.displayName,
            isRemote: info.isRemote,
            commitDate: info.commitDate,
            isHead: info.isHead
        )
    }
}
