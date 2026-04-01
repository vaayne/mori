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
    assertEqual(wt.stagedCount, 0)
    assertEqual(wt.modifiedCount, 0)
    assertEqual(wt.untrackedCount, 0)
    assertTrue(wt.hasUpstream)
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
        stagedCount: 3,
        modifiedCount: 2,
        untrackedCount: 1,
        hasUpstream: false,
        agentState: .running,
        status: .active
    )
    let data = try! JSONEncoder().encode(wt)
    let decoded = try! JSONDecoder().decode(Worktree.self, from: data)
    assertEqual(decoded, wt)
    assertEqual(decoded.stagedCount, 3)
    assertEqual(decoded.modifiedCount, 2)
    assertEqual(decoded.untrackedCount, 1)
    assertFalse(decoded.hasUpstream)
}

func testWorktreeCodableBackwardsCompat() {
    // Simulate JSON from older version without stagedCount/modifiedCount/untrackedCount
    let id = UUID()
    let projectId = UUID()
    let json = """
    {
        "id": "\(id.uuidString)",
        "projectId": "\(projectId.uuidString)",
        "name": "main",
        "path": "/repos/test",
        "isMainWorktree": true,
        "isDetached": false,
        "hasUncommittedChanges": true,
        "aheadCount": 1,
        "behindCount": 2,
        "unreadCount": 0,
        "agentState": "none",
        "status": "active"
    }
    """
    let decoded = try! JSONDecoder().decode(Worktree.self, from: json.data(using: .utf8)!)
    assertEqual(decoded.id, id)
    assertEqual(decoded.hasUncommittedChanges, true)
    assertEqual(decoded.aheadCount, 1)
    assertEqual(decoded.behindCount, 2)
    assertEqual(decoded.stagedCount, 0)
    assertEqual(decoded.modifiedCount, 0)
    assertEqual(decoded.untrackedCount, 0)
    assertTrue(decoded.hasUpstream)
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
    assertEqual(state.sidebarMode, .workspaces)
    assertEqual(state.searchQuery, "")
}

func testUIStateCodable() {
    let state = UIState(
        selectedProjectId: UUID(),
        selectedWorktreeId: UUID(),
        selectedWindowId: "@1",
        sidebarMode: .tasks,
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

// MARK: - Unread Flow Tests

/// Tests verifying unread badge flow from window-level to worktree and project aggregation.
/// The actual UnreadTracker (app target) sets hasUnreadOutput on RuntimeWindow;
/// these tests verify StatusAggregator correctly derives badges and aggregates.

func testUnreadWindowProducesBlueBadge() {
    // A window with unread output should get .unread badge
    let badge = StatusAggregator.windowBadge(hasUnreadOutput: true)
    assertEqual(badge, .unread)

    // A window without unread output should get .idle badge
    let idleBadge = StatusAggregator.windowBadge(hasUnreadOutput: false)
    assertEqual(idleBadge, .idle)
}

func testUnreadRollupToWorktree() {
    // Worktree with one unread window → .unread alert state
    let state = StatusAggregator.worktreeAlertState(
        windowBadges: [.idle, .unread, .idle],
        hasUncommittedChanges: false
    )
    assertEqual(state, .unread)
}

func testUnreadRollupToProject() {
    // Project with worktrees having unread counts → sum
    let totalUnread = StatusAggregator.projectUnreadCount(worktreeUnreadCounts: [2, 0, 3])
    assertEqual(totalUnread, 5)

    // Project alert state from worktrees with unread
    let projectState = StatusAggregator.projectAlertState(worktreeStates: [.none, .unread])
    assertEqual(projectState, .unread)
}

func testClearedUnreadReturnsToIdle() {
    // When unread is cleared (hasUnreadOutput = false), badge goes back to idle
    let badge = StatusAggregator.windowBadge(hasUnreadOutput: false)
    assertEqual(badge, .idle)

    // Worktree with all idle windows → .none alert state
    let state = StatusAggregator.worktreeAlertState(
        windowBadges: [.idle, .idle],
        hasUncommittedChanges: false
    )
    assertEqual(state, .none)

    // Project with zero unread
    let count = StatusAggregator.projectUnreadCount(worktreeUnreadCounts: [0, 0])
    assertEqual(count, 0)
}

func testUnreadDoesNotOverrideHigherPriority() {
    // Error > unread: worktree with both error and unread → error wins
    let state = StatusAggregator.worktreeAlertState(
        windowBadges: [.unread, .error],
        hasUncommittedChanges: false
    )
    assertEqual(state, .error)

    // Waiting > unread
    let waitingState = StatusAggregator.worktreeAlertState(
        windowBadges: [.unread, .waiting],
        hasUncommittedChanges: false
    )
    assertEqual(waitingState, .waiting)
}

func testUnreadOverridesDirty() {
    // Unread > dirty: worktree with unread windows + dirty git → unread wins
    let state = StatusAggregator.worktreeAlertState(
        windowBadges: [.unread],
        hasUncommittedChanges: true
    )
    assertEqual(state, .unread)
}

func testMultipleUnreadWindowsCountCorrectly() {
    // Multiple unread windows should each contribute to unreadCount
    // (Simulating what updateUnreadCounts does)
    let windows = [
        RuntimeWindow(tmuxWindowId: "@1", worktreeId: UUID(), hasUnreadOutput: true),
        RuntimeWindow(tmuxWindowId: "@2", worktreeId: UUID(), hasUnreadOutput: false),
        RuntimeWindow(tmuxWindowId: "@3", worktreeId: UUID(), hasUnreadOutput: true),
    ]
    let unreadCount = windows.filter { $0.hasUnreadOutput }.count
    assertEqual(unreadCount, 2)
}

// MARK: - FuzzyMatcher Tests

func testFuzzyMatcherExactPrefix() {
    // Exact prefix should score > 0 and higher than non-prefix
    let prefixScore = FuzzyMatcher.score(query: "mori", candidate: "mori-project")
    let nonPrefixScore = FuzzyMatcher.score(query: "mori", candidate: "my-mori")
    assertTrue(prefixScore > 0, "prefix match should score > 0")
    assertTrue(prefixScore > nonPrefixScore, "prefix should beat non-prefix")
}

func testFuzzyMatcherWordBoundary() {
    // Query matching start of a word (not first word) should beat mid-word
    let wordBoundaryScore = FuzzyMatcher.score(query: "side", candidate: "feat-sidebar")
    let midWordScore = FuzzyMatcher.score(query: "idea", candidate: "feat-sidebar")
    assertTrue(wordBoundaryScore > 0, "word boundary match should score > 0")
    assertTrue(wordBoundaryScore > midWordScore, "word boundary should beat mid-word")
    // Word boundary match for "bar" at underscore
    let barScore = FuzzyMatcher.score(query: "bar", candidate: "foo_bar_baz")
    assertTrue(barScore > 0, "word boundary after underscore should match")
}

func testFuzzyMatcherSubstring() {
    // Substring match should score > 0
    let score1 = FuzzyMatcher.score(query: "ject", candidate: "project")
    let score2 = FuzzyMatcher.score(query: "ori", candidate: "mori")
    assertTrue(score1 > 0, "substring should match")
    assertTrue(score2 > 0, "substring should match")
}

func testFuzzyMatcherNoMatch() {
    // No match returns 0
    assertEqual(FuzzyMatcher.score(query: "xyz", candidate: "mori"), 0)
    assertEqual(FuzzyMatcher.score(query: "abc", candidate: "def"), 0)
}

func testFuzzyMatcherEmptyQuery() {
    // Empty query matches everything with max score
    let score = FuzzyMatcher.score(query: "", candidate: "anything")
    assertTrue(score > 0, "empty query should match everything")
    let emptyBoth = FuzzyMatcher.score(query: "", candidate: "")
    assertTrue(emptyBoth > 0, "empty query + empty candidate should match")
}

func testFuzzyMatcherCaseInsensitive() {
    // Case-insensitive: same query different case should produce same score
    let upper = FuzzyMatcher.score(query: "MORI", candidate: "mori")
    let lower = FuzzyMatcher.score(query: "mori", candidate: "mori")
    assertEqual(upper, lower)
    let mixed = FuzzyMatcher.score(query: "mori", candidate: "MORI")
    assertEqual(upper, mixed)
}

func testFuzzyMatcherCamelCaseBoundary() {
    // camelCase word boundaries: "palette" at boundary scores higher than mid-word
    let boundaryScore = FuzzyMatcher.score(query: "palette", candidate: "commandPalette")
    let prefixScore = FuzzyMatcher.score(query: "command", candidate: "commandPalette")
    assertTrue(boundaryScore > 0, "camelCase boundary should match")
    assertTrue(prefixScore > boundaryScore, "prefix should beat camelCase boundary")
}

func testFuzzyMatcherScoreOrdering() {
    // Verify relative ordering: prefix > word boundary > mid-word substring
    // Use same candidate and similar-length queries for fair comparison
    let prefixScore = FuzzyMatcher.score(query: "crea", candidate: "create-worktree")
    let wordScore = FuzzyMatcher.score(query: "work", candidate: "create-worktree")
    let subScore = FuzzyMatcher.score(query: "orkt", candidate: "create-worktree")
    assertTrue(prefixScore > wordScore, "prefix should beat word boundary")
    assertTrue(wordScore > subScore, "word boundary should beat substring")
}

func testFuzzyMatcherNonContiguous() {
    // Non-contiguous character matching (core fuzzy feature)
    let score1 = FuzzyMatcher.score(query: "opr", candidate: "Open Project")
    assertTrue(score1 > 0, "'opr' should fuzzy match 'Open Project'")

    let score2 = FuzzyMatcher.score(query: "cw", candidate: "Create Worktree")
    assertTrue(score2 > 0, "'cw' should fuzzy match 'Create Worktree'")

    let score3 = FuzzyMatcher.score(query: "fbb", candidate: "foo_bar_baz")
    assertTrue(score3 > 0, "'fbb' should fuzzy match 'foo_bar_baz'")

    // Non-contiguous should score lower than contiguous
    let contiguous = FuzzyMatcher.score(query: "open", candidate: "Open Project")
    assertTrue(contiguous > score1, "contiguous should beat non-contiguous")
}

func testFuzzyMatcherNonContiguousNoMatch() {
    // Characters present but in wrong order should not match
    assertEqual(FuzzyMatcher.score(query: "ba", candidate: "ab"), 0)
    assertEqual(FuzzyMatcher.score(query: "zyx", candidate: "xyz"), 0)
}

// MARK: - WindowTag Tests

func testWindowTagRawValues() {
    assertEqual(WindowTag.shell.rawValue, "shell")
    assertEqual(WindowTag.editor.rawValue, "editor")
    assertEqual(WindowTag.agent.rawValue, "agent")
    assertEqual(WindowTag.server.rawValue, "server")
    assertEqual(WindowTag.logs.rawValue, "logs")
    assertEqual(WindowTag.tests.rawValue, "tests")
}

func testWindowTagCodable() {
    for tag: WindowTag in [.shell, .editor, .agent, .server, .logs, .tests] {
        let data = try! JSONEncoder().encode(tag)
        let decoded = try! JSONDecoder().decode(WindowTag.self, from: data)
        assertEqual(decoded, tag)
    }
}

func testWindowTagSymbolNames() {
    assertEqual(WindowTag.shell.symbolName, "terminal")
    assertEqual(WindowTag.editor.symbolName, "pencil")
    assertEqual(WindowTag.agent.symbolName, "cpu")
    assertEqual(WindowTag.server.symbolName, "server.rack")
    assertEqual(WindowTag.logs.symbolName, "doc.text")
    assertEqual(WindowTag.tests.symbolName, "checkmark.circle")
}

func testWindowTagInference() {
    assertEqual(WindowTag.infer(from: "shell"), .shell)
    assertEqual(WindowTag.infer(from: "editor"), .editor)
    assertEqual(WindowTag.infer(from: "agent"), .agent)
    assertEqual(WindowTag.infer(from: "my-agent"), .agent)
    assertEqual(WindowTag.infer(from: "server"), .server)
    assertEqual(WindowTag.infer(from: "dev-server"), .server)
    assertEqual(WindowTag.infer(from: "logs"), .logs)
    assertEqual(WindowTag.infer(from: "app-logs"), .logs)
    assertEqual(WindowTag.infer(from: "tests"), .tests)
    assertEqual(WindowTag.infer(from: "test-runner"), .tests)
    assertEqual(WindowTag.infer(from: "zsh"), .shell)
    assertEqual(WindowTag.infer(from: "random-name"), .shell)
}

func testWindowTagInferenceCaseInsensitive() {
    assertEqual(WindowTag.infer(from: "Agent"), .agent)
    assertEqual(WindowTag.infer(from: "LOGS"), .logs)
    assertEqual(WindowTag.infer(from: "Server"), .server)
    assertEqual(WindowTag.infer(from: "Editor"), .editor)
    assertEqual(WindowTag.infer(from: "Tests"), .tests)
}

func testRuntimeWindowWithTag() {
    let win = RuntimeWindow(
        tmuxWindowId: "@1",
        worktreeId: UUID(),
        title: "editor",
        tag: .editor
    )
    assertEqual(win.tag, .editor)
}

func testRuntimeWindowTagDefaultNil() {
    let win = RuntimeWindow(tmuxWindowId: "@1", worktreeId: UUID())
    assertNil(win.tag)
}

func testRuntimeWindowWithTagCodable() {
    let win = RuntimeWindow(
        tmuxWindowId: "@3",
        worktreeId: UUID(),
        title: "agent",
        tag: .agent
    )
    let data = try! JSONEncoder().encode(win)
    let decoded = try! JSONDecoder().decode(RuntimeWindow.self, from: data)
    assertEqual(decoded.tag, .agent)
    assertEqual(decoded, win)
}

func testWindowBadgeLongRunning() {
    assertEqual(WindowBadge.longRunning.rawValue, "longRunning")

    // Codable round-trip
    let data = try! JSONEncoder().encode(WindowBadge.longRunning)
    let decoded = try! JSONDecoder().decode(WindowBadge.self, from: data)
    assertEqual(decoded, .longRunning)
}

func testAlertStateFromLongRunningBadge() {
    assertEqual(StatusAggregator.alertState(from: .longRunning), .warning)
}

func testWorktreeAlertStateWithLongRunning() {
    // longRunning maps to .warning, which is above .unread but below .waiting
    let state = StatusAggregator.worktreeAlertState(windowBadges: [.longRunning, .unread])
    assertEqual(state, .warning)

    // waiting > longRunning
    let waitingState = StatusAggregator.worktreeAlertState(windowBadges: [.longRunning, .waiting])
    assertEqual(waitingState, .waiting)
}

// MARK: - StatusAggregator Richer Badge Tests

func testWindowBadgeRicherPriority() {
    // error > waiting > longRunning > running > unread > idle
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: true,
            agentState: .error
        ),
        .error
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: true,
            agentState: .waitingForInput
        ),
        .waiting
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: true,
            agentState: .running
        ),
        .longRunning
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: false,
            agentState: .none
        ),
        .running
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: false, isLongRunning: false,
            agentState: .none
        ),
        .unread
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: false, isLongRunning: false,
            agentState: .none
        ),
        .idle
    )
}

func testWindowBadgeAgentCompleted() {
    // Completed agent state returns .agentDone (higher priority than unread/idle)
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: false, isLongRunning: false,
            agentState: .completed
        ),
        .agentDone
    )
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: false, isLongRunning: false,
            agentState: .completed
        ),
        .agentDone
    )
}

// MARK: - RuntimeWindow Enhanced Fields Tests

func testRuntimeWindowEnhancedDefaults() {
    let win = RuntimeWindow(tmuxWindowId: "@1", worktreeId: UUID())
    assertFalse(win.isRunning)
    assertFalse(win.isLongRunning)
    assertEqual(win.agentState, .none)
    assertNil(win.lastExitCode)
}

func testRuntimeWindowEnhancedInit() {
    let win = RuntimeWindow(
        tmuxWindowId: "@4",
        worktreeId: UUID(),
        title: "agent",
        tag: .agent,
        lastExitCode: 1,
        isRunning: true,
        isLongRunning: true,
        agentState: .error
    )
    assertTrue(win.isRunning)
    assertTrue(win.isLongRunning)
    assertEqual(win.agentState, .error)
    assertEqual(win.lastExitCode, 1)
}

func testRuntimeWindowEnhancedCodable() {
    let win = RuntimeWindow(
        tmuxWindowId: "@5",
        worktreeId: UUID(),
        title: "server",
        tag: .server,
        lastExitCode: 42,
        isRunning: true,
        isLongRunning: false,
        agentState: .running
    )
    let data = try! JSONEncoder().encode(win)
    let decoded = try! JSONDecoder().decode(RuntimeWindow.self, from: data)
    assertEqual(decoded, win)
    assertEqual(decoded.isRunning, true)
    assertEqual(decoded.isLongRunning, false)
    assertEqual(decoded.agentState, .running)
    assertEqual(decoded.lastExitCode, 42)
}

// MARK: - Enhanced Status Aggregation Tests

func testWindowBadgeAllInputCombinations() {
    // Running only -> .running
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: true, isLongRunning: false,
            agentState: .none
        ),
        .running
    )

    // LongRunning overrides running
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: true, isLongRunning: true,
            agentState: .none
        ),
        .longRunning
    )

    // Agent error overrides everything
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: true,
            agentState: .error
        ),
        .error
    )

    // Agent waiting overrides longRunning/running
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: true, isLongRunning: true,
            agentState: .waitingForInput
        ),
        .waiting
    )

    // Agent running doesn't override longRunning
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: true, isLongRunning: true,
            agentState: .running
        ),
        .longRunning
    )

    // Agent completed alone -> agentDone
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: false, isLongRunning: false,
            agentState: .completed
        ),
        .agentDone
    )

    // Unread only -> .unread
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: true, isRunning: false, isLongRunning: false,
            agentState: .none
        ),
        .unread
    )

    // Nothing -> .idle
    assertEqual(
        StatusAggregator.windowBadge(
            hasUnreadOutput: false, isRunning: false, isLongRunning: false,
            agentState: .none
        ),
        .idle
    )
}

func testWorktreeAggregationWithRunningErrorLongRunning() {
    // Worktree with running window -> info alert
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.running]),
        .info
    )

    // Worktree with error window -> error alert
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.running, .error]),
        .error
    )

    // Worktree with longRunning window -> warning alert
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.longRunning]),
        .warning
    )

    // Worktree with mix: error > longRunning > running
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.running, .longRunning, .error]),
        .error
    )

    // longRunning > running (warning > info)
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.running, .longRunning]),
        .warning
    )

    // waiting > longRunning
    assertEqual(
        StatusAggregator.worktreeAlertState(windowBadges: [.longRunning, .waiting]),
        .waiting
    )
}

func testAlertStateMappingForLongRunning() {
    // .longRunning badge maps to .warning AlertState
    assertEqual(StatusAggregator.alertState(from: .longRunning), .warning)

    // .running badge maps to .info AlertState
    assertEqual(StatusAggregator.alertState(from: .running), .info)

    // Verify warning sits between unread and waiting in priority
    assertTrue(AlertState.warning > AlertState.unread)
    assertTrue(AlertState.waiting > AlertState.warning)
}

func testWorktreeAggregationWithGitAndRunning() {
    // Running + dirty: dirty(.dirty) > running(.info)
    assertEqual(
        StatusAggregator.worktreeAlertState(
            windowBadges: [.running],
            hasUncommittedChanges: true
        ),
        .dirty
    )

    // LongRunning + dirty: longRunning(.warning) > dirty(.dirty)
    assertEqual(
        StatusAggregator.worktreeAlertState(
            windowBadges: [.longRunning],
            hasUncommittedChanges: true
        ),
        .warning
    )
}

func testTemplateRegistryTags() {
    // Basic template tags (single shell window)
    assertEqual(TemplateRegistry.basic.windows.count, 1)
    assertEqual(TemplateRegistry.basic.windows[0].tag, .shell)

    // Go template tags
    assertEqual(TemplateRegistry.go.windows[0].tag, .editor)
    assertEqual(TemplateRegistry.go.windows[1].tag, .server)
    assertEqual(TemplateRegistry.go.windows[2].tag, .tests)
    assertEqual(TemplateRegistry.go.windows[3].tag, .logs)

    // Agent template tags
    assertEqual(TemplateRegistry.agent.windows[0].tag, .editor)
    assertEqual(TemplateRegistry.agent.windows[1].tag, .agent)
    assertEqual(TemplateRegistry.agent.windows[2].tag, .server)
    assertEqual(TemplateRegistry.agent.windows[3].tag, .logs)
}

// MARK: - NotificationDebouncer Tests

func testDebouncerIdleToWaiting() {
    var debouncer = NotificationDebouncer()
    let now = Date()
    let result = debouncer.shouldNotify(
        windowId: "@1", oldBadge: .idle, newBadge: .waiting, now: now
    )
    assertEqual(result, .agentWaiting)
}

func testDebouncerIdleToError() {
    var debouncer = NotificationDebouncer()
    let now = Date()
    let result = debouncer.shouldNotify(
        windowId: "@1", oldBadge: .idle, newBadge: .error, now: now
    )
    assertEqual(result, .commandError)
}

func testDebouncerRunningToIdle() {
    // running -> idle should trigger longRunningComplete
    var debouncer = NotificationDebouncer()
    let now = Date()
    let result = debouncer.shouldNotify(
        windowId: "@1", oldBadge: .running, newBadge: .idle, now: now
    )
    assertEqual(result, .longRunningComplete)
}

func testDebouncerLongRunningToIdle() {
    // longRunning -> idle should trigger longRunningComplete
    var debouncer = NotificationDebouncer()
    let now = Date()
    let result = debouncer.shouldNotify(
        windowId: "@1", oldBadge: .longRunning, newBadge: .idle, now: now
    )
    assertEqual(result, .longRunningComplete)
}

func testDebouncerSameBadgeNoNotification() {
    var debouncer = NotificationDebouncer()
    let now = Date()
    // idle -> idle: no notification
    let r1 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .idle, now: now)
    assertNil(r1)
    // running -> running: no notification
    let r2 = debouncer.shouldNotify(windowId: "@2", oldBadge: .running, newBadge: .running, now: now)
    assertNil(r2)
    // error -> error: no notification
    let r3 = debouncer.shouldNotify(windowId: "@3", oldBadge: .error, newBadge: .error, now: now)
    assertNil(r3)
}

func testDebouncerNonNotifyTransitions() {
    var debouncer = NotificationDebouncer()
    let now = Date()
    // idle -> running: no notification (running isn't notification-worthy on its own)
    let r1 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .running, now: now)
    assertNil(r1)
    // idle -> unread: no notification
    let r2 = debouncer.shouldNotify(windowId: "@2", oldBadge: .idle, newBadge: .unread, now: now)
    assertNil(r2)
    // idle -> longRunning: no notification
    let r3 = debouncer.shouldNotify(windowId: "@3", oldBadge: .idle, newBadge: .longRunning, now: now)
    assertNil(r3)
}

func testDebouncerSuppressionWithin30s() {
    var debouncer = NotificationDebouncer()
    let now = Date()

    // First fire should succeed
    let r1 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .waiting, now: now)
    assertEqual(r1, .agentWaiting)

    // Same event within 30s should be suppressed
    let within = now.addingTimeInterval(15)
    let r2 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .waiting, now: within)
    assertNil(r2)

    // After 30s should fire again
    let after = now.addingTimeInterval(31)
    let r3 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .waiting, now: after)
    assertEqual(r3, .agentWaiting)
}

func testDebouncerMultipleWindowsIndependent() {
    var debouncer = NotificationDebouncer()
    let now = Date()

    // Window @1 fires waiting
    let r1 = debouncer.shouldNotify(windowId: "@1", oldBadge: .idle, newBadge: .waiting, now: now)
    assertEqual(r1, .agentWaiting)

    // Window @2 fires waiting at same time — not suppressed (different window)
    let r2 = debouncer.shouldNotify(windowId: "@2", oldBadge: .idle, newBadge: .waiting, now: now)
    assertEqual(r2, .agentWaiting)

    // Window @1 fires error — not suppressed (different event type)
    let r3 = debouncer.shouldNotify(windowId: "@1", oldBadge: .waiting, newBadge: .error, now: now)
    assertEqual(r3, .commandError)
}

func testDebouncerNilOldBadgeTreatedAsIdle() {
    var debouncer = NotificationDebouncer()
    let now = Date()

    // nil old badge (new window) going to waiting -> should notify
    let r1 = debouncer.shouldNotify(windowId: "@1", oldBadge: nil, newBadge: .waiting, now: now)
    assertEqual(r1, .agentWaiting)

    // nil old badge going to idle -> no notification
    let r2 = debouncer.shouldNotify(windowId: "@2", oldBadge: nil, newBadge: .idle, now: now)
    assertNil(r2)
}

func testNotificationEventRawValues() {
    assertEqual(NotificationEvent.agentWaiting.rawValue, "agentWaiting")
    assertEqual(NotificationEvent.commandError.rawValue, "commandError")
    assertEqual(NotificationEvent.longRunningComplete.rawValue, "longRunningComplete")
}

func testDebouncerErrorToIdle() {
    // error -> idle: no longRunningComplete (only running/longRunning transitions)
    var debouncer = NotificationDebouncer()
    let now = Date()
    let result = debouncer.shouldNotify(windowId: "@1", oldBadge: .error, newBadge: .idle, now: now)
    assertNil(result)
}

// MARK: - HookConfig Tests

func testHookEventRawValues() {
    assertEqual(HookEvent.onWorktreeCreate.rawValue, "onWorktreeCreate")
    assertEqual(HookEvent.onWorktreeFocus.rawValue, "onWorktreeFocus")
    assertEqual(HookEvent.onWorktreeClose.rawValue, "onWorktreeClose")
    assertEqual(HookEvent.onWindowCreate.rawValue, "onWindowCreate")
    assertEqual(HookEvent.onWindowFocus.rawValue, "onWindowFocus")
    assertEqual(HookEvent.onWindowClose.rawValue, "onWindowClose")
}

func testHookEventCodable() {
    for event: HookEvent in [
        .onWorktreeCreate, .onWorktreeFocus, .onWorktreeClose,
        .onWindowCreate, .onWindowFocus, .onWindowClose
    ] {
        let data = try! JSONEncoder().encode(event)
        let decoded = try! JSONDecoder().decode(HookEvent.self, from: data)
        assertEqual(decoded, event)
    }
}

func testHookActionWithShell() {
    let action = HookAction(shell: "echo hello")
    assertEqual(action.shell, "echo hello")
    assertNil(action.tmuxSend)

    let data = try! JSONEncoder().encode(action)
    let decoded = try! JSONDecoder().decode(HookAction.self, from: data)
    assertEqual(decoded, action)
}

func testHookActionWithTmuxSend() {
    let action = HookAction(tmuxSend: "ls -la")
    assertNil(action.shell)
    assertEqual(action.tmuxSend, "ls -la")

    let data = try! JSONEncoder().encode(action)
    let decoded = try! JSONDecoder().decode(HookAction.self, from: data)
    assertEqual(decoded, action)
}

func testHookActionWithBoth() {
    let action = HookAction(shell: "echo hi", tmuxSend: "pwd")
    assertEqual(action.shell, "echo hi")
    assertEqual(action.tmuxSend, "pwd")
}

func testHookEntryEncodeDecode() {
    let entry = HookEntry(
        event: .onWorktreeCreate,
        actions: [HookAction(shell: "git fetch")]
    )
    let data = try! JSONEncoder().encode(entry)
    let decoded = try! JSONDecoder().decode(HookEntry.self, from: data)
    assertEqual(decoded, entry)
    assertEqual(decoded.event, .onWorktreeCreate)
    assertEqual(decoded.actions.count, 1)
    assertEqual(decoded.actions[0].shell, "git fetch")
}

func testHookConfigFullJsonDecode() {
    let json = """
    {
        "hooks": [
            {
                "event": "onWorktreeCreate",
                "actions": [
                    {"shell": "echo created"},
                    {"tmuxSend": "ls"}
                ]
            },
            {
                "event": "onWindowFocus",
                "actions": [
                    {"shell": "date >> /tmp/focus.log"}
                ]
            }
        ]
    }
    """.data(using: .utf8)!

    let config = try! JSONDecoder().decode(HookConfig.self, from: json)
    assertEqual(config.hooks.count, 2)
    assertEqual(config.hooks[0].event, .onWorktreeCreate)
    assertEqual(config.hooks[0].actions.count, 2)
    assertEqual(config.hooks[0].actions[0].shell, "echo created")
    assertEqual(config.hooks[0].actions[1].tmuxSend, "ls")
    assertEqual(config.hooks[1].event, .onWindowFocus)
    assertEqual(config.hooks[1].actions.count, 1)
}

func testHookConfigActionsForEvent() {
    let config = HookConfig(hooks: [
        HookEntry(event: .onWorktreeCreate, actions: [
            HookAction(shell: "echo a"),
            HookAction(tmuxSend: "b"),
        ]),
        HookEntry(event: .onWindowFocus, actions: [
            HookAction(shell: "echo c"),
        ]),
        HookEntry(event: .onWorktreeCreate, actions: [
            HookAction(shell: "echo d"),
        ]),
    ])

    // Should collect actions from all matching entries
    let createActions = config.actions(for: .onWorktreeCreate)
    assertEqual(createActions.count, 3)
    assertEqual(createActions[0].shell, "echo a")
    assertEqual(createActions[1].tmuxSend, "b")
    assertEqual(createActions[2].shell, "echo d")

    let focusActions = config.actions(for: .onWindowFocus)
    assertEqual(focusActions.count, 1)
    assertEqual(focusActions[0].shell, "echo c")

    // No matching event -> empty
    let closeActions = config.actions(for: .onWindowClose)
    assertEqual(closeActions.count, 0)
}

func testHookConfigEmptyHooks() {
    let config = HookConfig()
    assertEqual(config.hooks.count, 0)
    assertEqual(config.actions(for: .onWorktreeCreate).count, 0)
}

func testHookConfigEmptyJsonDecode() {
    let json = """
    {"hooks": []}
    """.data(using: .utf8)!

    let config = try! JSONDecoder().decode(HookConfig.self, from: json)
    assertEqual(config.hooks.count, 0)
}

func testHookConfigInvalidJsonReturnsNil() {
    // Invalid JSON should fail to decode (caller handles gracefully)
    let invalid = "not json".data(using: .utf8)!
    let result = try? JSONDecoder().decode(HookConfig.self, from: invalid)
    assertNil(result)
}

func testHookConfigMissingFieldsFails() {
    // Missing "hooks" key
    let json = """
    {"events": []}
    """.data(using: .utf8)!
    let result = try? JSONDecoder().decode(HookConfig.self, from: json)
    assertNil(result)
}

func testHookEntryMatchByEvent() {
    let entries = [
        HookEntry(event: .onWorktreeCreate, actions: [HookAction(shell: "a")]),
        HookEntry(event: .onWindowClose, actions: [HookAction(shell: "b")]),
        HookEntry(event: .onWorktreeFocus, actions: [HookAction(shell: "c")]),
    ]
    let matched = entries.filter { $0.event == .onWindowClose }
    assertEqual(matched.count, 1)
    assertEqual(matched[0].actions[0].shell, "b")
}

// MARK: - WorkflowStatus Tests

func testWorkflowStatusRawValues() {
    assertEqual(WorkflowStatus.todo.rawValue, "todo")
    assertEqual(WorkflowStatus.inProgress.rawValue, "inProgress")
    assertEqual(WorkflowStatus.needsReview.rawValue, "needsReview")
    assertEqual(WorkflowStatus.done.rawValue, "done")
    assertEqual(WorkflowStatus.cancelled.rawValue, "cancelled")
}

func testWorkflowStatusCodableRoundTrip() {
    for status in WorkflowStatus.allCases {
        let data = try! JSONEncoder().encode(status)
        let decoded = try! JSONDecoder().decode(WorkflowStatus.self, from: data)
        assertEqual(decoded, status)
    }
}

func testWorkflowStatusSortOrder() {
    assertEqual(WorkflowStatus.inProgress.sortOrder, 0)
    assertEqual(WorkflowStatus.needsReview.sortOrder, 1)
    assertEqual(WorkflowStatus.todo.sortOrder, 2)
    assertEqual(WorkflowStatus.done.sortOrder, 3)
    assertEqual(WorkflowStatus.cancelled.sortOrder, 4)

    // Verify ordering: inProgress < needsReview < todo < done < cancelled
    let sorted = WorkflowStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
    assertEqual(sorted, [.inProgress, .needsReview, .todo, .done, .cancelled])
}

func testWorkflowStatusDisplayName() {
    assertEqual(WorkflowStatus.todo.displayName, "To Do")
    assertEqual(WorkflowStatus.inProgress.displayName, "In Progress")
    assertEqual(WorkflowStatus.needsReview.displayName, "Needs Review")
    assertEqual(WorkflowStatus.done.displayName, "Done")
    assertEqual(WorkflowStatus.cancelled.displayName, "Cancelled")
}

func testWorkflowStatusIconName() {
    assertEqual(WorkflowStatus.todo.iconName, "circle")
    assertEqual(WorkflowStatus.inProgress.iconName, "circle.dotted.circle")
    assertEqual(WorkflowStatus.needsReview.iconName, "eye.circle")
    assertEqual(WorkflowStatus.done.iconName, "checkmark.circle.fill")
    assertEqual(WorkflowStatus.cancelled.iconName, "xmark.circle")
}

func testWorktreeWorkflowStatusDefault() {
    let wt = Worktree(projectId: UUID(), name: "main", path: "/test")
    assertEqual(wt.workflowStatus, .todo)
}

func testWorktreeWorkflowStatusCodable() {
    let wt = Worktree(
        projectId: UUID(),
        name: "feat",
        path: "/test/feat",
        workflowStatus: .inProgress
    )
    let data = try! JSONEncoder().encode(wt)
    let decoded = try! JSONDecoder().decode(Worktree.self, from: data)
    assertEqual(decoded.workflowStatus, .inProgress)
}

func testWorktreeCodableBackwardsCompatWorkflowStatus() {
    // Simulate JSON from older version without workflowStatus field
    let id = UUID()
    let projectId = UUID()
    let json = """
    {
        "id": "\(id.uuidString)",
        "projectId": "\(projectId.uuidString)",
        "name": "main",
        "path": "/repos/test",
        "isMainWorktree": true,
        "isDetached": false,
        "hasUncommittedChanges": false,
        "aheadCount": 0,
        "behindCount": 0,
        "unreadCount": 0,
        "agentState": "none",
        "status": "active"
    }
    """
    let decoded = try! JSONDecoder().decode(Worktree.self, from: json.data(using: .utf8)!)
    assertEqual(decoded.workflowStatus, .todo)
}

func testWorktreeCodableWithWorkflowStatus() {
    // JSON with explicit workflowStatus should preserve it
    let id = UUID()
    let projectId = UUID()
    let json = """
    {
        "id": "\(id.uuidString)",
        "projectId": "\(projectId.uuidString)",
        "name": "feat",
        "path": "/repos/feat",
        "isMainWorktree": false,
        "isDetached": false,
        "hasUncommittedChanges": true,
        "aheadCount": 1,
        "behindCount": 0,
        "unreadCount": 0,
        "agentState": "none",
        "status": "active",
        "workflowStatus": "needsReview"
    }
    """
    let decoded = try! JSONDecoder().decode(Worktree.self, from: json.data(using: .utf8)!)
    assertEqual(decoded.workflowStatus, .needsReview)
}

func testSidebarModeNewValuesRoundTrip() {
    for mode: SidebarMode in [.workspaces, .tasks] {
        let data = try! JSONEncoder().encode(mode)
        let decoded = try! JSONDecoder().decode(SidebarMode.self, from: data)
        assertEqual(decoded, mode)
    }
}

func testSidebarModeBackwardsCompatWorktrees() {
    // Old "worktrees" value should map to .workspaces
    let json = "\"worktrees\"".data(using: .utf8)!
    let decoded = try! JSONDecoder().decode(SidebarMode.self, from: json)
    assertEqual(decoded, .workspaces)
}

func testSidebarModeBackwardsCompatSearch() {
    // Old "search" value should map to .workspaces
    let json = "\"search\"".data(using: .utf8)!
    let decoded = try! JSONDecoder().decode(SidebarMode.self, from: json)
    assertEqual(decoded, .workspaces)
}

func testSidebarModeBackwardsCompatAgents() {
    // Old "agents" value should map to .tasks
    let json = "\"agents\"".data(using: .utf8)!
    let decoded = try! JSONDecoder().decode(SidebarMode.self, from: json)
    assertEqual(decoded, .tasks)
}

// MARK: - AgentMessage Tests

func testAgentMessageEnvelope() {
    let msg = AgentMessage(
        fromProject: "mori",
        fromWorktree: "main",
        fromWindow: "claude",
        fromPaneId: "%5",
        text: "Review the auth module"
    )
    assertEqual(msg.envelope, "[mori-bridge project:mori worktree:main window:claude pane:%5] Review the auth module")
}

func testAgentMessageParse() {
    let envelope = "[mori-bridge project:mori worktree:main window:claude pane:%5] Review the auth module"
    let msg = AgentMessage.parse(envelope)
    assertNotNil(msg)
    assertEqual(msg?.fromProject, "mori")
    assertEqual(msg?.fromWorktree, "main")
    assertEqual(msg?.fromWindow, "claude")
    assertEqual(msg?.fromPaneId, "%5")
    assertEqual(msg?.text, "Review the auth module")
}

func testAgentMessageParseSlashInWorktree() {
    let envelope = "[mori-bridge project:mori worktree:feature/auth window:codex pane:%3] hello"
    let msg = AgentMessage.parse(envelope)
    assertNotNil(msg)
    assertEqual(msg?.fromProject, "mori")
    assertEqual(msg?.fromWorktree, "feature/auth")
    assertEqual(msg?.fromWindow, "codex")
    assertEqual(msg?.fromPaneId, "%3")
    assertEqual(msg?.text, "hello")
}

func testAgentMessageParseInvalid() {
    assertNil(AgentMessage.parse("not a valid envelope"))
    assertNil(AgentMessage.parse("[mori-bridge project:incomplete"))
    assertNil(AgentMessage.parse(""))
}

func testAgentMessageCodable() {
    let msg = AgentMessage(
        fromProject: "api",
        fromWorktree: "feat",
        fromWindow: "codex",
        fromPaneId: "%1",
        text: "hello"
    )
    let data = try! JSONEncoder().encode(msg)
    let decoded = try! JSONDecoder().decode(AgentMessage.self, from: data)
    assertEqual(decoded, msg, "AgentMessage codable round-trip")
}

// MARK: - Main

print("=== MoriCore Model Tests ===")

testProjectDefaultInit()
testProjectFullInit()
testProjectEquatable()
testProjectCodable()

testWorktreeDefaultInit()
testWorktreeCodable()
testWorktreeCodableBackwardsCompat()

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

testUnreadWindowProducesBlueBadge()
testUnreadRollupToWorktree()
testUnreadRollupToProject()
testClearedUnreadReturnsToIdle()
testUnreadDoesNotOverrideHigherPriority()
testUnreadOverridesDirty()
testMultipleUnreadWindowsCountCorrectly()

testFuzzyMatcherExactPrefix()
testFuzzyMatcherWordBoundary()
testFuzzyMatcherSubstring()
testFuzzyMatcherNoMatch()
testFuzzyMatcherEmptyQuery()
testFuzzyMatcherCaseInsensitive()
testFuzzyMatcherCamelCaseBoundary()
testFuzzyMatcherScoreOrdering()
testFuzzyMatcherNonContiguous()
testFuzzyMatcherNonContiguousNoMatch()

testWindowTagRawValues()
testWindowTagCodable()
testWindowTagSymbolNames()
testWindowTagInference()
testWindowTagInferenceCaseInsensitive()
testRuntimeWindowWithTag()
testRuntimeWindowTagDefaultNil()
testRuntimeWindowWithTagCodable()
testWindowBadgeLongRunning()
testAlertStateFromLongRunningBadge()
testWorktreeAlertStateWithLongRunning()
testWindowBadgeRicherPriority()
testWindowBadgeAgentCompleted()

testRuntimeWindowEnhancedDefaults()
testRuntimeWindowEnhancedInit()
testRuntimeWindowEnhancedCodable()
testWindowBadgeAllInputCombinations()
testWorktreeAggregationWithRunningErrorLongRunning()
testAlertStateMappingForLongRunning()
testWorktreeAggregationWithGitAndRunning()

testTemplateRegistryTags()

testDebouncerIdleToWaiting()
testDebouncerIdleToError()
testDebouncerRunningToIdle()
testDebouncerLongRunningToIdle()
testDebouncerSameBadgeNoNotification()
testDebouncerNonNotifyTransitions()
testDebouncerSuppressionWithin30s()
testDebouncerMultipleWindowsIndependent()
testDebouncerNilOldBadgeTreatedAsIdle()
testNotificationEventRawValues()
testDebouncerErrorToIdle()

testHookEventRawValues()
testHookEventCodable()
testHookActionWithShell()
testHookActionWithTmuxSend()
testHookActionWithBoth()
testHookEntryEncodeDecode()
testHookConfigFullJsonDecode()
testHookConfigActionsForEvent()
testHookConfigEmptyHooks()
testHookConfigEmptyJsonDecode()
testHookConfigInvalidJsonReturnsNil()
testHookConfigMissingFieldsFails()
testHookEntryMatchByEvent()

testWorkflowStatusRawValues()
testWorkflowStatusCodableRoundTrip()
testWorkflowStatusSortOrder()
testWorkflowStatusDisplayName()
testWorkflowStatusIconName()
testWorktreeWorkflowStatusDefault()
testWorktreeWorkflowStatusCodable()
testWorktreeCodableBackwardsCompatWorkflowStatus()
testWorktreeCodableWithWorkflowStatus()
testSidebarModeNewValuesRoundTrip()
testSidebarModeBackwardsCompatWorktrees()
testSidebarModeBackwardsCompatSearch()
testSidebarModeBackwardsCompatAgents()

testSSHControlSocketPathLengthLimit()
testSSHExecutionConfigTargetFormatting()
testSSHRemovingBatchMode()
testSSHShellEscape()
testSSHAskPassEnvironmentIsMinimal()
testSSHCreateAskPassScriptHasSecurePermissions()

// AgentMessage
testAgentMessageEnvelope()
testAgentMessageParse()
testAgentMessageParseSlashInWorktree()
testAgentMessageParseInvalid()
testAgentMessageCodable()

// KeyBinding
runKeyBindingTests()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
