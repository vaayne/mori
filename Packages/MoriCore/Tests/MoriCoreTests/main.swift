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

printResults()

if failCount > 0 {
    fatalError("Tests failed")
}
