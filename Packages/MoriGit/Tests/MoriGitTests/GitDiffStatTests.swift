import Foundation
import MoriGit

// MARK: - GitDiffStat.parseShortstat Tests

func testParseShortstatBoth() {
    let stat = GitDiffStat.parseShortstat(" 3 files changed, 312 insertions(+), 332 deletions(-)")
    assertEqual(stat.additions, 312)
    assertEqual(stat.deletions, 332)
    assertEqual(stat.hasMergeConflicts, nil)
}

func testParseShortstatInsertionsOnly() {
    let stat = GitDiffStat.parseShortstat(" 1 file changed, 1 insertion(+)")
    assertEqual(stat.additions, 1)
    assertEqual(stat.deletions, 0)
}

func testParseShortstatDeletionsOnly() {
    let stat = GitDiffStat.parseShortstat(" 2 files changed, 96 deletions(-)")
    assertEqual(stat.additions, 0)
    assertEqual(stat.deletions, 96)
}

func testParseShortstatEmpty() {
    let stat = GitDiffStat.parseShortstat("")
    assertEqual(stat.additions, 0)
    assertEqual(stat.deletions, 0)
}

func testParseShortstatConflictsPassthrough() {
    let stat = GitDiffStat.parseShortstat(" 1 file changed, 1 insertion(+)", hasMergeConflicts: true)
    assertEqual(stat.hasMergeConflicts, true)
}
