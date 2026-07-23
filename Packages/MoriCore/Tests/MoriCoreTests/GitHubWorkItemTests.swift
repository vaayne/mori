import Foundation
import MoriCore

// MARK: - List parsing

func testGitHubWorkItemParseIssueList() {
    let json = """
    [{"number":12,"title":"Fix login crash"},
     {"number":3,"title":"Add dark mode"}]
    """
    let items = GitHubWorkItem.parse(listJSON: Data(json.utf8), kind: .issue)
    assertEqual(items.count, 2)
    assertEqual(items[0].kind, .issue)
    assertEqual(items[0].number, 12)
    assertEqual(items[0].title, "Fix login crash")
    assertNil(items[0].headRefName)
    assertFalse(items[0].isDraft)
    assertEqual(items[1].number, 3)
}

func testGitHubWorkItemParsePRList() {
    let json = """
    [{"number":91,"title":"Redesign sidebar","headRefName":"feat/sidebar","isDraft":false},
     {"number":92,"title":"WIP refactor","headRefName":"wip-refactor","isDraft":true}]
    """
    let items = GitHubWorkItem.parse(listJSON: Data(json.utf8), kind: .pullRequest)
    assertEqual(items.count, 2)
    assertEqual(items[0].kind, .pullRequest)
    assertEqual(items[0].headRefName, "feat/sidebar")
    assertFalse(items[0].isDraft)
    assertEqual(items[1].headRefName, "wip-refactor")
    assertTrue(items[1].isDraft)
}

func testGitHubWorkItemParseObject() {
    let json = """
    {"number":42,"title":"Single PR","headRefName":"pr-head","isDraft":true}
    """
    let item = GitHubWorkItem.parse(objectJSON: Data(json.utf8), kind: .pullRequest)
    assertNotNil(item)
    assertEqual(item?.number, 42)
    assertEqual(item?.headRefName, "pr-head")
    assertEqual(item?.isDraft, true)
}

func testGitHubWorkItemParseInvalidReturnsEmpty() {
    assertEqual(GitHubWorkItem.parse(listJSON: Data("not json".utf8), kind: .issue).count, 0)
    assertNil(GitHubWorkItem.parse(objectJSON: Data("not json".utf8), kind: .pullRequest))
}

// MARK: - URL parsing

func testGitHubWorkItemParseURL() {
    let issue = GitHubWorkItem.parseURL("https://github.com/vaayne/mori/issues/128")
    assertEqual(issue?.kind, .issue)
    assertEqual(issue?.number, 128)

    let pr = GitHubWorkItem.parseURL("https://github.com/vaayne/mori/pull/7")
    assertEqual(pr?.kind, .pullRequest)
    assertEqual(pr?.number, 7)

    // Trailing path/fragment tolerated.
    let withFragment = GitHubWorkItem.parseURL("https://github.com/o/r/pull/9/files#diff-abc")
    assertEqual(withFragment?.kind, .pullRequest)
    assertEqual(withFragment?.number, 9)
}

func testGitHubWorkItemParseURLRejectsNonGitHub() {
    assertNil(GitHubWorkItem.parseURL("https://gitlab.com/o/r/issues/1"))
    assertNil(GitHubWorkItem.parseURL("https://github.com/o/r/commits/main"))
    assertNil(GitHubWorkItem.parseURL("just some text"))
    assertNil(GitHubWorkItem.parseURL("https://github.com/o/r/issues/notanumber"))
    assertNil(GitHubWorkItem.parseURL("https://github.com/o/r"))
}

// MARK: - Issue branch naming

func testGitHubWorkItemIssueBranchName() {
    assertEqual(
        GitHubWorkItem.issueBranchName(number: 42, title: "Fix the Login Crash"),
        "issue-42-fix-the-login-crash"
    )
    // Punctuation collapses to single hyphens, no leading/trailing hyphen.
    assertEqual(
        GitHubWorkItem.issueBranchName(number: 7, title: "  Add: dark-mode (v2)!  "),
        "issue-7-add-dark-mode-v2"
    )
}

func testGitHubWorkItemIssueBranchNameDegradesToNumber() {
    // CJK-only title has no ASCII alphanumerics → bare issue-<number>.
    assertEqual(GitHubWorkItem.issueBranchName(number: 5, title: "登录崩溃修复"), "issue-5")
    // Empty title.
    assertEqual(GitHubWorkItem.issueBranchName(number: 9, title: ""), "issue-9")
    // Punctuation-only title.
    assertEqual(GitHubWorkItem.issueBranchName(number: 3, title: "!!! ??? ..."), "issue-3")
}

func testGitHubWorkItemIssueBranchNameTrimsAtWordBoundary() {
    let long = "this is a very long issue title that keeps going well past forty characters"
    let name = GitHubWorkItem.issueBranchName(number: 1, title: long)
    let slug = String(name.dropFirst("issue-1-".count))
    assertTrue(slug.count <= 40, "slug trimmed to <= 40 chars, got \(slug.count): \(slug)")
    assertFalse(slug.hasSuffix("-"), "no dangling trailing hyphen")
    // Cut happens at a word boundary, so no partial trailing word fragment.
    assertTrue(name.hasPrefix("issue-1-this-is-a-very-long-issue-title-that"), "got \(name)")
}

func runGitHubWorkItemTests() {
    testGitHubWorkItemParseIssueList()
    testGitHubWorkItemParsePRList()
    testGitHubWorkItemParseObject()
    testGitHubWorkItemParseInvalidReturnsEmpty()
    testGitHubWorkItemParseURL()
    testGitHubWorkItemParseURLRejectsNonGitHub()
    testGitHubWorkItemIssueBranchName()
    testGitHubWorkItemIssueBranchNameDegradesToNumber()
    testGitHubWorkItemIssueBranchNameTrimsAtWordBoundary()
}
