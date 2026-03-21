import Foundation
import MoriGit

// Tab delimiter used by GitBranchParser (matches git format string)
private let tab = "\t"

// MARK: - GitBranchParser Tests

func testParseBranchLocal() {
    let output = "main\(tab)*\(tab)1710900000\(tab)origin/main\n"
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
    let output = "origin/feature/dark-mode\(tab)\(tab)1710700000\(tab)\n"
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
    main\(tab)*\(tab)1710900000\(tab)origin/main
    feature/auth\(tab)\(tab)1710800000\(tab)origin/feature/auth
    origin/feature/dark-mode\(tab)\(tab)1710700000\(tab)
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
    let output = "main\(tab)*\(tab)\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "main")
    assertTrue(branches[0].isHead)
    assertNil(branches[0].commitDate)
}

func testParseBranchNoUpstream() {
    let output = "develop\(tab)\(tab)1710800000\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "develop")
    assertFalse(branches[0].isHead)
    assertNil(branches[0].trackingBranch)
}

func testParseBranchCustomRemote() {
    let output = """
    upstream/main\(tab)\(tab)1710900000\(tab)
    fork/feature\(tab)\(tab)1710800000\(tab)
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
    let output = "main\(tab)\(tab)1710900000\(tab)origin/main\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertFalse(branches[0].isHead)
}

func testParseBranchCommitDate() {
    let output = "main\(tab)*\(tab)1710900000\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    let expectedDate = Date(timeIntervalSince1970: 1710900000)
    assertEqual(branches[0].commitDate, expectedDate)
}

func testParseBranchMalformedLine() {
    // Line with only delimiters (empty name)
    let output = "\(tab)\(tab)\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 0, "Empty name should be skipped")
}

func testParseBranchMinimalFields() {
    // Line with only a name (no delimiters) — still valid
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

// MARK: - GitBranchParser Edge Case Tests

func testParseBranchMultipleSlashes() {
    let output = "feature/auth/v2\(tab)\(tab)1710800000\(tab)origin/feature/auth/v2\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "feature/auth/v2")
    assertFalse(branches[0].isRemote, "feature/auth/v2 should be local")
    assertEqual(branches[0].displayName, "feature/auth/v2")
    assertEqual(branches[0].trackingBranch, "origin/feature/auth/v2")
}

func testParseBranchRemoteMultipleSlashes() {
    let output = "origin/feature/auth/v2\(tab)\(tab)1710800000\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "origin/feature/auth/v2")
    assertTrue(branches[0].isRemote)
    assertEqual(branches[0].displayName, "feature/auth/v2")
    assertEqual(branches[0].remoteName, "origin")
}

func testParseBranchNoRemotesAtAll() {
    let output = """
    main\(tab)*\(tab)1710900000\(tab)
    develop\(tab)\(tab)1710800000\(tab)
    feature/sidebar\(tab)\(tab)1710700000\(tab)
    """
    let branches = GitBranchParser.parse(output, remoteNames: [])
    assertEqual(branches.count, 3)
    for branch in branches {
        assertFalse(branch.isRemote, "\(branch.name) should be local with empty remote names")
        assertNil(branch.trackingBranch)
    }
    assertTrue(branches[0].isHead)
}

func testParseBranchHundreds() {
    var lines: [String] = []
    for i in 0..<200 {
        let date = 1710900000 - (i * 3600)
        lines.append("branch-\(i)\(tab)\(tab)\(date)\(tab)")
    }
    let output = lines.joined(separator: "\n")
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 200, "Should parse all 200 branches")
    assertEqual(branches[0].name, "branch-0")
    assertEqual(branches[199].name, "branch-199")
}

func testParseBranchMalformedMixedWithValid() {
    // Malformed lines: empty name (tab-only), blank lines — should be skipped
    let lines = [
        "main\(tab)*\(tab)1710900000\(tab)origin/main",
        "\(tab)\(tab)\(tab)",           // empty name → skipped
        "",                              // blank line → skipped
        "feature/auth\(tab)\(tab)1710800000\(tab)",
        "\(tab)\(tab)baddate\(tab)",     // empty name → skipped
        "origin/develop\(tab)\(tab)1710700000\(tab)",
    ]
    let output = lines.joined(separator: "\n")
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 3, "Should parse 3 valid branches, skip malformed")
    assertEqual(branches[0].name, "main")
    assertEqual(branches[1].name, "feature/auth")
    assertEqual(branches[2].name, "origin/develop")
}

func testParseBranchRemoteWithoutLocal() {
    let output = """
    main\(tab)*\(tab)1710900000\(tab)origin/main
    origin/feature/only-remote\(tab)\(tab)1710700000\(tab)
    """
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 2)
    assertEqual(branches[0].name, "main")
    assertFalse(branches[0].isRemote)
    assertEqual(branches[1].name, "origin/feature/only-remote")
    assertTrue(branches[1].isRemote)
    assertEqual(branches[1].displayName, "feature/only-remote")
}

// MARK: - GitBranchInfo Boundary Tests

func testGitBranchInfoDisplayNameDeepNesting() {
    let remote = GitBranchInfo(name: "origin/user/feature/deep/path", isRemote: true)
    assertEqual(remote.displayName, "user/feature/deep/path")
    assertEqual(remote.remoteName, "origin")
}

func testGitBranchInfoEquality() {
    let a = GitBranchInfo(name: "main", isRemote: false, commitDate: Date(timeIntervalSince1970: 1000), isHead: true)
    let b = GitBranchInfo(name: "main", isRemote: false, commitDate: Date(timeIntervalSince1970: 1000), isHead: true)
    let c = GitBranchInfo(name: "develop", isRemote: false, commitDate: Date(timeIntervalSince1970: 1000), isHead: false)
    assertEqual(a, b)
    assertNotEqual(a, c)
}

func testGitBranchInfoCodableRoundTrip() {
    let branch = GitBranchInfo(
        name: "origin/feature/auth",
        isRemote: true,
        commitDate: Date(timeIntervalSince1970: 1710900000),
        isHead: false,
        trackingBranch: nil
    )
    let data = try! JSONEncoder().encode(branch)
    let decoded = try! JSONDecoder().decode(GitBranchInfo.self, from: data)
    assertEqual(decoded, branch)
    assertEqual(decoded.displayName, "feature/auth")
    assertEqual(decoded.remoteName, "origin")
}

func testGitBranchInfoLocalWithSlashNotRemote() {
    let branch = GitBranchInfo(name: "feature/auth", isRemote: false)
    assertNil(branch.remoteName, "Local branch with slash should not have remoteName")
    assertEqual(branch.displayName, "feature/auth", "Local branch displayName should be same as name")
}

func testParseBranchWithPipeInName() {
    // Branch names CAN contain `|` (git allows it). Tab delimiter avoids this conflict.
    let output = "feat|pipe\(tab)*\(tab)1710900000\(tab)\n"
    let branches = GitBranchParser.parse(output)
    assertEqual(branches.count, 1)
    assertEqual(branches[0].name, "feat|pipe", "Branch with pipe in name should parse correctly")
    assertTrue(branches[0].isHead)
}
