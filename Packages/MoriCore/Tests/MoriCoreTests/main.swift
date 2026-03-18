import Foundation
import MoriCore

// MARK: - Project Tests

func testProjectDefaultInit() {
    let project = Project(name: "mori", repoRootPath: "/Users/test/mori")
    assertEqual(project.name, "mori")
    assertEqual(project.repoRootPath, "/Users/test/mori")
    assertEqual(project.gitCommonDir, "")
    assertNil(project.originURL)
    assertNil(project.iconName)
    assertFalse(project.isFavorite)
    assertFalse(project.isCollapsed)
    assertNil(project.lastActiveAt)
    assertEqual(project.aggregateUnreadCount, 0)
    assertEqual(project.aggregateAlertState, .none)
}

func testProjectFullInit() {
    let id = UUID()
    let date = Date()
    let project = Project(
        id: id,
        name: "anna",
        repoRootPath: "/repos/anna",
        gitCommonDir: "/repos/anna/.git",
        originURL: "git@github.com:user/anna.git",
        iconName: "folder",
        isFavorite: true,
        isCollapsed: true,
        lastActiveAt: date,
        aggregateUnreadCount: 5,
        aggregateAlertState: .warning
    )
    assertEqual(project.id, id)
    assertEqual(project.name, "anna")
    assertEqual(project.originURL, "git@github.com:user/anna.git")
    assertTrue(project.isFavorite)
    assertEqual(project.aggregateUnreadCount, 5)
    assertEqual(project.aggregateAlertState, .warning)
}

func testProjectEquatable() {
    let id = UUID()
    let a = Project(id: id, name: "a", repoRootPath: "/a")
    let b = Project(id: id, name: "a", repoRootPath: "/a")
    let c = Project(id: id, name: "c", repoRootPath: "/a")
    assertEqual(a, b)
    assertNotEqual(a, c)
}

func testProjectCodable() {
    let project = Project(name: "test", repoRootPath: "/test")
    let data = try! JSONEncoder().encode(project)
    let decoded = try! JSONDecoder().decode(Project.self, from: data)
    assertEqual(decoded, project)
}

// MARK: - Worktree Tests

func testWorktreeDefaultInit() {
    let projectId = UUID()
    let wt = Worktree(projectId: projectId, name: "main", path: "/repos/anna")
    assertEqual(wt.projectId, projectId)
    assertEqual(wt.name, "main")
    assertNil(wt.branch)
    assertFalse(wt.isMainWorktree)
    assertFalse(wt.isDetached)
    assertFalse(wt.hasUncommittedChanges)
    assertEqual(wt.aheadCount, 0)
    assertEqual(wt.behindCount, 0)
    assertNil(wt.tmuxSessionId)
    assertNil(wt.tmuxSessionName)
    assertEqual(wt.unreadCount, 0)
    assertEqual(wt.agentState, .none)
    assertEqual(wt.status, .active)
}

func testWorktreeCodable() {
    let wt = Worktree(
        projectId: UUID(),
        name: "feat-sidebar",
        path: "/repos/anna/feat-sidebar",
        branch: "feat/sidebar",
        agentState: .running,
        status: .active
    )
    let data = try! JSONEncoder().encode(wt)
    let decoded = try! JSONDecoder().decode(Worktree.self, from: data)
    assertEqual(decoded, wt)
}

// MARK: - RuntimeWindow Tests

func testRuntimeWindowIdDerivation() {
    let win = RuntimeWindow(tmuxWindowId: "@1", worktreeId: UUID())
    assertEqual(win.id, "@1")
}

func testRuntimeWindowDefaults() {
    let win = RuntimeWindow(tmuxWindowId: "@1", worktreeId: UUID())
    assertEqual(win.tmuxWindowIndex, 0)
    assertEqual(win.title, "")
    assertEqual(win.paneCount, 1)
    assertFalse(win.hasUnreadOutput)
    assertNil(win.badge)
}

func testRuntimeWindowCodable() {
    let win = RuntimeWindow(
        tmuxWindowId: "@2",
        worktreeId: UUID(),
        tmuxWindowIndex: 1,
        title: "editor",
        paneCount: 2,
        badge: .running
    )
    let data = try! JSONEncoder().encode(win)
    let decoded = try! JSONDecoder().decode(RuntimeWindow.self, from: data)
    assertEqual(decoded, win)
}

// MARK: - RuntimePane Tests

func testRuntimePaneIdDerivation() {
    let pane = RuntimePane(tmuxPaneId: "%0", tmuxWindowId: "@1")
    assertEqual(pane.id, "%0")
}

func testRuntimePaneDefaults() {
    let pane = RuntimePane(tmuxPaneId: "%0", tmuxWindowId: "@1")
    assertFalse(pane.isActive)
    assertFalse(pane.isZoomed)
    assertNil(pane.title)
    assertNil(pane.cwd)
    assertNil(pane.tty)
}

func testRuntimePaneCodable() {
    let pane = RuntimePane(
        tmuxPaneId: "%1",
        tmuxWindowId: "@2",
        title: "zsh",
        cwd: "/home",
        tty: "/dev/ttys001",
        isActive: true,
        isZoomed: false
    )
    let data = try! JSONEncoder().encode(pane)
    let decoded = try! JSONDecoder().decode(RuntimePane.self, from: data)
    assertEqual(decoded, pane)
}

// MARK: - UIState Tests

func testUIStateDefaultInit() {
    let state = UIState()
    assertNil(state.selectedProjectId)
    assertNil(state.selectedWorktreeId)
    assertNil(state.selectedWindowId)
    assertEqual(state.sidebarMode, .worktrees)
    assertEqual(state.searchQuery, "")
}

func testUIStateCodable() {
    let state = UIState(
        selectedProjectId: UUID(),
        selectedWorktreeId: UUID(),
        selectedWindowId: "@1",
        sidebarMode: .search,
        searchQuery: "test"
    )
    let data = try! JSONEncoder().encode(state)
    let decoded = try! JSONDecoder().decode(UIState.self, from: data)
    assertEqual(decoded, state)
}

// MARK: - Enum Tests

func testEnumRawValues() {
    assertEqual(AgentState.none.rawValue, "none")
    assertEqual(AgentState.running.rawValue, "running")
    assertEqual(AgentState.waitingForInput.rawValue, "waitingForInput")
    assertEqual(AgentState.error.rawValue, "error")
    assertEqual(AgentState.completed.rawValue, "completed")

    assertEqual(WorktreeStatus.active.rawValue, "active")
    assertEqual(WorktreeStatus.inactive.rawValue, "inactive")
    assertEqual(WorktreeStatus.unavailable.rawValue, "unavailable")

    assertEqual(WindowBadge.idle.rawValue, "idle")
    assertEqual(WindowBadge.unread.rawValue, "unread")
    assertEqual(WindowBadge.error.rawValue, "error")

    assertEqual(AlertState.none.rawValue, "none")
    assertEqual(AlertState.warning.rawValue, "warning")
    assertEqual(AlertState.error.rawValue, "error")
}

// MARK: - StatusAggregator Tests

func testWindowBadgeFromUnread() {
    assertEqual(StatusAggregator.windowBadge(hasUnreadOutput: true), .unread)
    assertEqual(StatusAggregator.windowBadge(hasUnreadOutput: false), .idle)
}

func testAlertStateFromBadge() {
    assertEqual(StatusAggregator.alertState(from: .idle), .none)
    assertEqual(StatusAggregator.alertState(from: .unread), .unread)
    assertEqual(StatusAggregator.alertState(from: .running), .info)
    assertEqual(StatusAggregator.alertState(from: .waiting), .waiting)
    assertEqual(StatusAggregator.alertState(from: .error), .error)
}

func testWorktreeAlertStateFromWindowBadges() {
    // All idle -> none
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: [.idle, .idle]), .none)

    // Unread is highest
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: [.idle, .unread]), .unread)

    // Error wins over everything
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: [.unread, .error, .idle]), .error)

    // Waiting > unread
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: [.unread, .waiting]), .waiting)

    // Running maps to info, which is less than unread
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: [.running, .unread]), .unread)

    // Empty -> none
    assertEqual(StatusAggregator.worktreeAlertState(windowBadges: []), .none)
}

func testWorktreeAlertStateWithGitDirty() {
    // Dirty alone -> dirty
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.idle], hasUncommittedChanges: true),
        .dirty
    )

    // Dirty is less than unread
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.unread], hasUncommittedChanges: true),
        .unread
    )

    // Clean + idle -> none
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.idle], hasUncommittedChanges: false),
        .none
    )

    // Dirty + error -> error wins
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.error], hasUncommittedChanges: true),
        .error
    )
}

func testProjectAlertStateAggregation() {
    // Max wins
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: [.none, .dirty, .error]), .error)
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: [.none, .unread]), .unread)
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: [.dirty, .waiting]), .waiting)

    // Empty -> none
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: []), .none)

    // Single
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: [.dirty]), .dirty)

    // All none
    assertEqual(StatusAggregator.projectAlertState(worktreeStates: [.none, .none]), .none)
}

func testProjectUnreadCount() {
    assertEqual(StatusAggregator.projectUnreadCount(worktreeUnreadCounts: [1, 2, 3]), 6)
    assertEqual(StatusAggregator.projectUnreadCount(worktreeUnreadCounts: []), 0)
    assertEqual(StatusAggregator.projectUnreadCount(worktreeUnreadCounts: [0, 0]), 0)
    assertEqual(StatusAggregator.projectUnreadCount(worktreeUnreadCounts: [5]), 5)
}

func testAlertStateComparable() {
    // Priority: error > waiting > warning > unread > dirty > info > none
    assertTrue(AlertState.error > AlertState.waiting)
    assertTrue(AlertState.waiting > AlertState.warning)
    assertTrue(AlertState.warning > AlertState.unread)
    assertTrue(AlertState.unread > AlertState.dirty)
    assertTrue(AlertState.dirty > AlertState.info)
    assertTrue(AlertState.info > AlertState.none)

    // Max works correctly
    let states: [AlertState] = [.none, .dirty, .unread, .error]
    assertEqual(states.max(), .error)
}

func testAlertStateNewCasesCodable() {
    // Verify new cases round-trip through JSON
    for state: AlertState in [.dirty, .unread, .waiting] {
        let data = try! JSONEncoder().encode(state)
        let decoded = try! JSONDecoder().decode(AlertState.self, from: data)
        assertEqual(decoded, state)
    }
}

// MARK: - Main

print("=== MoriCore Model Tests ===")

testProjectDefaultInit()
testProjectFullInit()
testProjectEquatable()
testProjectCodable()

testWorktreeDefaultInit()
testWorktreeCodable()

testRuntimeWindowIdDerivation()
testRuntimeWindowDefaults()
testRuntimeWindowCodable()

testRuntimePaneIdDerivation()
testRuntimePaneDefaults()
testRuntimePaneCodable()

testUIStateDefaultInit()
testUIStateCodable()

testEnumRawValues()

testWindowBadgeFromUnread()
testAlertStateFromBadge()
testWorktreeAlertStateFromWindowBadges()
testWorktreeAlertStateWithGitDirty()
testProjectAlertStateAggregation()
testProjectUnreadCount()
testAlertStateComparable()
testAlertStateNewCasesCodable()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
