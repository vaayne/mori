import Foundation
import MoriCore
import MoriPersistence

// MARK: - ProjectRepository Tests

func testProjectInsertAndFetch() throws {
    let store = JSONStore()
    let repo = ProjectRepository(store: store)

    let project = Project(
        name: "mori",
        repoRootPath: "/Users/test/mori",
        gitCommonDir: "/Users/test/mori/.git",
        originURL: "git@github.com:user/mori.git"
    )

    try repo.save(project)
    let fetched = try repo.fetch(id: project.id)

    assertNotNil(fetched)
    assertEqual(fetched?.id, project.id)
    assertEqual(fetched?.name, "mori")
    assertEqual(fetched?.repoRootPath, "/Users/test/mori")
    assertEqual(fetched?.gitCommonDir, "/Users/test/mori/.git")
    assertEqual(fetched?.originURL, "git@github.com:user/mori.git")
    assertEqual(fetched?.isFavorite, false)
    assertEqual(fetched?.aggregateAlertState, AlertState.none)
}

func testProjectFetchAll() throws {
    let store = JSONStore()
    let repo = ProjectRepository(store: store)

    let p1 = Project(name: "alpha", repoRootPath: "/alpha")
    let p2 = Project(name: "beta", repoRootPath: "/beta")

    try repo.save(p1)
    try repo.save(p2)

    let all = try repo.fetchAll()
    assertEqual(all.count, 2)
}

func testProjectUpdate() throws {
    let store = JSONStore()
    let repo = ProjectRepository(store: store)

    var project = Project(name: "old", repoRootPath: "/old")
    try repo.save(project)

    project.name = "new"
    project.isFavorite = true
    project.aggregateAlertState = .error
    try repo.save(project)

    let fetched = try repo.fetch(id: project.id)
    assertEqual(fetched?.name, "new")
    assertEqual(fetched?.isFavorite, true)
    assertEqual(fetched?.aggregateAlertState, .error)
}

func testProjectDelete() throws {
    let store = JSONStore()
    let repo = ProjectRepository(store: store)

    let project = Project(name: "doomed", repoRootPath: "/doomed")
    try repo.save(project)
    try repo.delete(id: project.id)

    let fetched = try repo.fetch(id: project.id)
    assertNil(fetched)
}

// MARK: - WorktreeRepository Tests

func testWorktreeInsertAndFetch() throws {
    let store = JSONStore()
    let projectRepo = ProjectRepository(store: store)
    let wtRepo = WorktreeRepository(store: store)

    let project = Project(name: "anna", repoRootPath: "/anna")
    try projectRepo.save(project)

    let wt = Worktree(
        projectId: project.id,
        name: "main",
        path: "/anna",
        branch: "main",
        isMainWorktree: true,
        tmuxSessionName: "anna/main"
    )
    try wtRepo.save(wt)

    let fetched = try wtRepo.fetchAll(forProject: project.id)
    assertEqual(fetched.count, 1)
    assertEqual(fetched.first?.name, "main")
    assertEqual(fetched.first?.branch, "main")
    assertEqual(fetched.first?.isMainWorktree, true)
    assertEqual(fetched.first?.tmuxSessionName, "anna/main")
    assertEqual(fetched.first?.agentState, AgentState.none)
    assertEqual(fetched.first?.status, .active)
}

func testWorktreeFetchById() throws {
    let store = JSONStore()
    let projectRepo = ProjectRepository(store: store)
    let wtRepo = WorktreeRepository(store: store)

    let project = Project(name: "anna", repoRootPath: "/anna")
    try projectRepo.save(project)

    let wt = Worktree(projectId: project.id, name: "feat", path: "/anna/feat")
    try wtRepo.save(wt)

    let fetched = try wtRepo.fetch(id: wt.id)
    assertNotNil(fetched)
    assertEqual(fetched?.id, wt.id)
}

func testWorktreeUpdate() throws {
    let store = JSONStore()
    let projectRepo = ProjectRepository(store: store)
    let wtRepo = WorktreeRepository(store: store)

    let project = Project(name: "anna", repoRootPath: "/anna")
    try projectRepo.save(project)

    var wt = Worktree(projectId: project.id, name: "main", path: "/anna")
    try wtRepo.save(wt)

    wt.branch = "develop"
    wt.hasUncommittedChanges = true
    wt.agentState = .running
    wt.status = .inactive
    try wtRepo.save(wt)

    let fetched = try wtRepo.fetch(id: wt.id)
    assertEqual(fetched?.branch, "develop")
    assertEqual(fetched?.hasUncommittedChanges, true)
    assertEqual(fetched?.agentState, .running)
    assertEqual(fetched?.status, .inactive)
}

func testWorktreeCascadeDelete() throws {
    let store = JSONStore()
    let projectRepo = ProjectRepository(store: store)
    let wtRepo = WorktreeRepository(store: store)

    let project = Project(name: "anna", repoRootPath: "/anna")
    try projectRepo.save(project)

    let wt1 = Worktree(projectId: project.id, name: "main", path: "/anna")
    let wt2 = Worktree(projectId: project.id, name: "feat", path: "/anna/feat")
    try wtRepo.save(wt1)
    try wtRepo.save(wt2)

    assertEqual(try wtRepo.fetchAll(forProject: project.id).count, 2)

    try projectRepo.delete(id: project.id)

    assertEqual(try wtRepo.fetchAll(forProject: project.id).count, 0)
}

func testWorktreeDelete() throws {
    let store = JSONStore()
    let projectRepo = ProjectRepository(store: store)
    let wtRepo = WorktreeRepository(store: store)

    let project = Project(name: "anna", repoRootPath: "/anna")
    try projectRepo.save(project)

    let wt = Worktree(projectId: project.id, name: "main", path: "/anna")
    try wtRepo.save(wt)
    try wtRepo.delete(id: wt.id)

    assertNil(try wtRepo.fetch(id: wt.id))
}

// MARK: - UIStateRepository Tests

func testUIStateDefault() throws {
    let store = JSONStore()
    let repo = UIStateRepository(store: store)

    let state = try repo.fetch()
    assertNil(state.selectedProjectId)
    assertNil(state.selectedWorktreeId)
    assertNil(state.selectedWindowId)
    assertEqual(state.sidebarMode, .worktrees)
    assertEqual(state.searchQuery, "")
}

func testUIStateSaveAndFetch() throws {
    let store = JSONStore()
    let repo = UIStateRepository(store: store)

    let projectId = UUID()
    let worktreeId = UUID()
    let state = UIState(
        selectedProjectId: projectId,
        selectedWorktreeId: worktreeId,
        selectedWindowId: "@3",
        sidebarMode: .search,
        searchQuery: "hello"
    )

    try repo.save(state)
    let fetched = try repo.fetch()

    assertEqual(fetched.selectedProjectId, projectId)
    assertEqual(fetched.selectedWorktreeId, worktreeId)
    assertEqual(fetched.selectedWindowId, "@3")
    assertEqual(fetched.sidebarMode, .search)
    assertEqual(fetched.searchQuery, "hello")
}

func testUIStateOverwrite() throws {
    let store = JSONStore()
    let repo = UIStateRepository(store: store)

    let state1 = UIState(selectedProjectId: UUID(), sidebarMode: .worktrees, searchQuery: "first")
    try repo.save(state1)

    let state2 = UIState(selectedProjectId: UUID(), sidebarMode: .search, searchQuery: "second")
    try repo.save(state2)

    let fetched = try repo.fetch()
    assertEqual(fetched.selectedProjectId, state2.selectedProjectId)
    assertEqual(fetched.sidebarMode, .search)
    assertEqual(fetched.searchQuery, "second")
}

// MARK: - JSONStore File I/O Tests

func testJSONStoreFileRoundTrip() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let project = Project(name: "disk-test", repoRootPath: "/disk")
    let worktree = Worktree(projectId: project.id, name: "main", path: "/disk")

    // Write via repositories
    let store1 = JSONStore(fileURL: tmp)
    let projectRepo = ProjectRepository(store: store1)
    let wtRepo = WorktreeRepository(store: store1)
    try projectRepo.save(project)
    try wtRepo.save(worktree)
    store1.mutate { $0.uiState.selectedProjectId = project.id }

    // Read back from a fresh store
    let store2 = JSONStore(fileURL: tmp)
    assertEqual(store2.data.projects.count, 1)
    assertEqual(store2.data.projects.first?.project.name, "disk-test")
    assertEqual(store2.data.projects.first?.worktrees.count, 1)
    assertEqual(store2.data.projects.first?.worktrees.first?.name, "main")
    assertEqual(store2.data.uiState.selectedProjectId, project.id)
}

// MARK: - Main

print("=== MoriPersistence JSON Store Tests ===")

do {
    try testProjectInsertAndFetch()
    try testProjectFetchAll()
    try testProjectUpdate()
    try testProjectDelete()

    try testWorktreeInsertAndFetch()
    try testWorktreeFetchById()
    try testWorktreeUpdate()
    try testWorktreeCascadeDelete()
    try testWorktreeDelete()

    try testUIStateDefault()
    try testUIStateSaveAndFetch()
    try testUIStateOverwrite()

    try testJSONStoreFileRoundTrip()
} catch {
    fputs("ERROR: \(error)\n", stderr)
    failCount += 1
}

printResults()

if failCount > 0 {
    exit(1)
}
