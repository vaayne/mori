import Foundation
import MoriGit

// MARK: - GitBranchParser Tests

func testParseBranchLocal() {
    let output = "main|*|1710900000|origin/main\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "main")
    assertFalse(branches[0].isRemote)
    assertTrue(branches[0].isHead)
    assertNotNil(branches[0].commitDate)
    assertEqual(branches[0].trackingBranch, "origin/main")
    assertEqual(branches[0].displayName, "main")
    assertNil(branches[0].remoteName)
}

func testParseBranchRemote() {
    let output = "origin/feature/dark-mode||1710700000|\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "origin/feature/dark-mode")
    assertTrue(branches[0].isRemote)
    assertFalse(branches[0].isHead)
    assertNotNil(branches[0].commitDate)
    assertNil(branches[0].trackingBranch)
    assertEqual(branches[0].displayName, "feature/dark-mode")
    assertEqual(branches[0].remoteName, "origin")
}

func testParseBranchMultiple() {
    let output = """
    main|*|1710900000|origin/main
    feature/auth||1710800000|origin/feature/auth
    origin/feature/dark-mode||1710700000|
    """
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 3)

    // First: local HEAD branch
    assertEqual(branches[0].name, "main")
    assertFalse(branches[0].isRemote)
    assertTrue(branches[0].isHead)

    // Second: local branch with slash
    assertEqual(branches[1].name, "feature/auth")
    assertFalse(branches[1].isRemote, "feature/auth should be local, not remote")
    assertFalse(branches[1].isHead)
    assertEqual(branches[1].trackingBranch, "origin/feature/auth")

    // Third: remote branch
    assertEqual(branches[2].name, "origin/feature/dark-mode")
    assertTrue(branches[2].isRemote)
    assertFalse(branches[2].isHead)
}

func testParseBranchEmpty() {
    let branches = GitBranchParser.parse("")
    assertEqual(branches.count, 0)
}

func testParseBranchWhitespaceOnly() {
    let branches = GitBranchParser.parse("   \n\n  \n")
    assertEqual(branches.count, 0)
}

func testParseBranchNoDate() {
    let output = "main|*||\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "main")
    assertTrue(branches[0].isHead)
    assertNil(branches[0].commitDate)
}

func testParseBranchNoUpstream() {
    let output = "develop||1710800000|\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "develop")
    assertFalse(branches[0].isHead)
    assertNil(branches[0].trackingBranch)
}

func testParseBranchCustomRemote() {
    let output = """
    upstream/main||1710900000|
    fork/feature||1710800000|
    """
    // Default remote names only includes "origin"
    let defaultBranches = GitBranchParser.parse(output)
    assertEqual(defaultBranches.count, 2)
    assertFalse(defaultBranches[0].isRemote, "upstream/main not detected with default remotes")
    assertFalse(defaultBranches[1].isRemote, "fork/feature not detected with default remotes")

    // With custom remote names
    let customBranches = GitBranchParser.parse(output, remoteNames: ["origin", "upstream", "fork"])
    assertEqual(customBranches.count, 2)
    assertTrue(customBranches[0].isRemote, "upstream/main detected with custom remotes")
    assertTrue(customBranches[1].isRemote, "fork/feature detected with custom remotes")
    assertEqual(customBranches[0].remoteName, "upstream")
    assertEqual(customBranches[1].remoteName, "fork")
}

func testParseBranchDetachedHead() {
    // When HEAD is detached, git branch -a may show "(HEAD detached at abc123)" as a branch name
    // with the format string, detached HEAD shows as the commit ref
    let output = "main||1710900000|origin/main\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    // No branch has isHead = true (detached HEAD doesn't mark any branch)
    assertFalse(branches[0].isHead)
}

func testParseBranchCommitDate() {
    let output = "main|*|1710900000|\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    let expectedDate = Date(timeIntervalSince1970: 1710900000)
    assertEqual(branches[0].commitDate, expectedDate)
}

func testParseBranchMalformedLine() {
    // Line with only delimiters
    let output = "|||\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 0, "Empty name should be skipped")
}

func testParseBranchMinimalFields() {
    // Line with only a name (no delimiters)
    let output = "main\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "main")
    assertFalse(branches[0].isRemote)
    assertFalse(branches[0].isHead)
    assertNil(branches[0].commitDate)
    assertNil(branches[0].trackingBranch)
}

func testGitBranchInfoDisplayName() {
    let local = GitBranchInfo(name: "feature/auth", isRemote: false)
    assertEqual(local.displayName, "feature/auth")

    let remote = GitBranchInfo(name: "origin/feature/auth", isRemote: true)
    assertEqual(remote.displayName, "feature/auth")

    let simpleRemote = GitBranchInfo(name: "origin/main", isRemote: true)
    assertEqual(simpleRemote.displayName, "main")

    let simpleLocal = GitBranchInfo(name: "main", isRemote: false)
    assertEqual(simpleLocal.displayName, "main")
}

func testGitBranchInfoRemoteName() {
    let local = GitBranchInfo(name: "main", isRemote: false)
    assertNil(local.remoteName)

    let remote = GitBranchInfo(name: "origin/main", isRemote: true)
    assertEqual(remote.remoteName, "origin")

    let upstreamRemote = GitBranchInfo(name: "upstream/develop", isRemote: true)
    assertEqual(upstreamRemote.remoteName, "upstream")
}
