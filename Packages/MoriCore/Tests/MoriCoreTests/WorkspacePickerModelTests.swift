import Foundation
import MoriCore

// MARK: - Fixtures

private func pickerFixture() -> WorkspacePickerModel {
    WorkspacePickerModel(
        branches: [
            PickerBranch(name: "main", isHead: true),
            PickerBranch(name: "feat/login"),
            PickerBranch(name: "fix/crash"),
            PickerBranch(name: "wip/spike"),
            PickerBranch(name: "origin/feat/remote-only", displayName: "feat/remote-only", isRemote: true),
        ],
        githubItems: [
            GitHubWorkItem(kind: .pullRequest, number: 42, title: "Redesign sidebar", headRefName: "feat/sidebar"),
            GitHubWorkItem(kind: .pullRequest, number: 43, title: "Excluded head", headRefName: "wip/spike"),
            GitHubWorkItem(kind: .issue, number: 7, title: "Fix login crash"),
        ],
        excludedBranches: ["wip/spike"]
    )
}

// MARK: - Default selection

func testPickerNewNamePreselectsCreateRow() {
    let model = pickerFixture()
    let rows = model.rows(for: "feat/brand-new")
    guard case .create(let name)? = rows.first else {
        assertTrue(false, "expected create row first, got \(String(describing: rows.first))")
        return
    }
    assertEqual(name, "feat/brand-new")
    assertEqual(model.defaultSelectionId(for: "feat/brand-new", in: rows), "create")
}

func testPickerExactBranchSelectsBranchRow() {
    let model = pickerFixture()
    let rows = model.rows(for: "feat/login")
    // Exact existing branch: no create row, the branch row is preselected.
    assertFalse(rows.contains(where: { if case .create = $0 { return true }; return false }))
    assertEqual(model.defaultSelectionId(for: "feat/login", in: rows), "branch-feat/login")
}

func testPickerHashNumberSelectsReferencedPR() {
    let model = pickerFixture()
    let rows = model.rows(for: "#42")
    assertEqual(model.defaultSelectionId(for: "#42", in: rows), "pr-42")
    // `#n` is a reference, never a creatable branch name.
    assertFalse(rows.contains(where: { if case .create = $0 { return true }; return false }))
}

func testPickerEmptyQuerySelectsNothing() {
    let model = pickerFixture()
    let rows = model.rows(for: "")
    assertNil(model.defaultSelectionId(for: "", in: rows))
    assertFalse(rows.isEmpty)
}

// MARK: - Hint rows

func testPickerExcludedBranchYieldsUnselectableHint() {
    let model = pickerFixture()
    let rows = model.rows(for: "wip/spike")
    guard case .branchAlreadyOpenHint(let name)? = rows.first else {
        assertTrue(false, "expected already-open hint, got \(String(describing: rows.first))")
        return
    }
    assertEqual(name, "wip/spike")
    assertFalse(rows[0].isSelectable)
    assertNil(model.defaultSelectionId(for: "wip/spike", in: rows))
    // The excluded branch must not appear as a checkout row either.
    assertFalse(rows.contains(where: {
        if case .branch(let b) = $0 { return b.name == "wip/spike" }
        return false
    }))
}

func testPickerUnknownPRURLYieldsHint() {
    let model = pickerFixture()
    let url = "https://github.com/owner/repo/pull/999"
    // Unknown PR URL is not rewritten...
    assertNil(model.normalizedQuery(for: url))
    // ...and explains itself instead of offering a create row.
    let rows = model.rows(for: url)
    guard case .unknownPRHint(let number)? = rows.first else {
        assertTrue(false, "expected unknown-PR hint, got \(String(describing: rows.first))")
        return
    }
    assertEqual(number, 999)
    assertFalse(rows[0].isSelectable)
}

// MARK: - URL normalization

func testPickerKnownPRURLNormalizesToHashQuery() {
    let model = pickerFixture()
    assertEqual(model.normalizedQuery(for: "https://github.com/owner/repo/pull/42"), "#42")
}

func testPickerUnknownIssueURLNormalizesToBranchName() {
    let model = pickerFixture()
    assertEqual(model.normalizedQuery(for: "https://github.com/owner/repo/issues/321"), "issue-321")
}

// MARK: - Section content

func testPickerExcludedHeadHidesPR() {
    let model = pickerFixture()
    let rows = model.rows(for: "")
    // PR 43's head branch already backs a workspace — the PR row is suppressed.
    assertFalse(rows.contains(where: { if case .pr(let item) = $0 { return item.number == 43 }; return false }))
    assertTrue(rows.contains(where: { if case .pr(let item) = $0 { return item.number == 42 }; return false }))
}

func testPickerRemoteExactMatchInsertsBranchRow() {
    let model = pickerFixture()
    let rows = model.rows(for: "feat/remote-only")
    assertTrue(rows.contains(where: {
        if case .branch(let b) = $0 { return b.name == "origin/feat/remote-only" && b.isRemote }
        return false
    }))
    assertEqual(model.defaultSelectionId(for: "feat/remote-only", in: rows), "branch-origin/feat/remote-only")
}

// MARK: - Identity across refreshes

func testPickerRowIdsStableAcrossDataRefresh() {
    let before = pickerFixture()
    // Same query, richer data: GitHub items landed and a new branch appeared.
    let after = WorkspacePickerModel(
        branches: before.branches + [PickerBranch(name: "feat/logout")],
        githubItems: before.githubItems + [GitHubWorkItem(kind: .issue, number: 8, title: "Login polish")],
        excludedBranches: before.excludedBranches
    )
    let query = "login"
    let beforeIds = before.rows(for: query).map(\.id)
    let afterIds = after.rows(for: query).map(\.id)
    // Every previously shown selectable row keeps its id even though sections
    // shifted — this is what lets the container restore the highlight.
    for id in beforeIds where !id.hasPrefix("header-") {
        assertTrue(afterIds.contains(id), "id \(id) lost across refresh")
    }
    assertNotEqual(beforeIds, afterIds, "fixture should actually change the row set")
}

// MARK: - Fetch generation

func testFetchGenerationDropsStaleAndOutOfOrderResults() {
    var gen = FetchGeneration()
    let first = gen.begin()
    let second = gen.begin()
    // Older fetch completing after a newer one started: dropped.
    assertFalse(gen.isCurrent(first))
    assertTrue(gen.isCurrent(second))
    // Invalidation (page deactivated) rejects even the newest token.
    gen.invalidate()
    assertFalse(gen.isCurrent(second))
}

// MARK: - Runner

func runWorkspacePickerModelTests() {
    testPickerNewNamePreselectsCreateRow()
    testPickerExactBranchSelectsBranchRow()
    testPickerHashNumberSelectsReferencedPR()
    testPickerEmptyQuerySelectsNothing()
    testPickerExcludedBranchYieldsUnselectableHint()
    testPickerUnknownPRURLYieldsHint()
    testPickerKnownPRURLNormalizesToHashQuery()
    testPickerUnknownIssueURLNormalizesToBranchName()
    testPickerExcludedHeadHidesPR()
    testPickerRemoteExactMatchInsertsBranchRow()
    testPickerRowIdsStableAcrossDataRefresh()
    testFetchGenerationDropsStaleAndOutOfOrderResults()
}
