import Foundation
import MoriCore

private func pr(_ json: String) -> PullRequestInfo? {
    PullRequestInfo.parse(jsonData: Data(json.utf8))
}

func testPullRequestParseOpenPassing() {
    let info = pr("""
    {"number":91,"title":"redesign sidebar","url":"https://github.com/o/r/pull/91",
     "state":"OPEN","isDraft":false,"reviewDecision":"REVIEW_REQUIRED",
     "statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},
                          {"status":"COMPLETED","conclusion":"NEUTRAL"}]}
    """)
    assertNotNil(info)
    assertEqual(info?.number, 91)
    assertEqual(info?.title, "redesign sidebar")
    assertEqual(info?.state, .open)
    assertFalse(info?.isDraft ?? true)
    assertEqual(info?.checks, .passing)
    assertEqual(info?.reviewDecision, .required)
}

func testPullRequestParseFailingCheckWins() {
    let info = pr("""
    {"number":1,"title":"x","url":"u","state":"OPEN",
     "statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},
                          {"status":"IN_PROGRESS","conclusion":""},
                          {"status":"COMPLETED","conclusion":"FAILURE"}]}
    """)
    assertEqual(info?.checks, .failing)
}

func testPullRequestParsePendingWhenRunning() {
    let info = pr("""
    {"number":2,"title":"x","url":"u","state":"OPEN",
     "statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},
                          {"status":"IN_PROGRESS","conclusion":""}]}
    """)
    assertEqual(info?.checks, .pending)
}

func testPullRequestParseStatusContextState() {
    // External StatusContext entries carry `state`, not conclusion.
    let info = pr("""
    {"number":3,"title":"x","url":"u","state":"OPEN",
     "statusCheckRollup":[{"state":"SUCCESS"},{"state":"PENDING"}]}
    """)
    assertEqual(info?.checks, .pending)
}

func testPullRequestParseNoChecks() {
    let info = pr("""
    {"number":4,"title":"x","url":"u","state":"OPEN","statusCheckRollup":[]}
    """)
    assertEqual(info?.checks, PullRequestInfo.Checks.none)
}

func testPullRequestParseDraftAndMerged() {
    let draft = pr("""
    {"number":5,"title":"wip","url":"u","state":"OPEN","isDraft":true}
    """)
    assertEqual(draft?.isDraft, true)
    assertEqual(draft?.checks, PullRequestInfo.Checks.none)

    let merged = pr("""
    {"number":6,"title":"done","url":"u","state":"MERGED","reviewDecision":"APPROVED"}
    """)
    assertEqual(merged?.state, .merged)
    assertEqual(merged?.reviewDecision, .approved)
}

func testPullRequestParseInvalidReturnsNil() {
    assertNil(pr("not json"))
    assertNil(pr("{\"title\":\"missing number\"}"))
}

func runPullRequestInfoTests() {
    testPullRequestParseOpenPassing()
    testPullRequestParseFailingCheckWins()
    testPullRequestParsePendingWhenRunning()
    testPullRequestParseStatusContextState()
    testPullRequestParseNoChecks()
    testPullRequestParseDraftAndMerged()
    testPullRequestParseInvalidReturnsNil()
}
