import Foundation
import MoriGit

print("=== MoriGit Tests ===")

// GitWorktreeParser tests
testParseWorktreeSingle()
testParseWorktreeMultiple()
testParseWorktreeDetached()
testParseWorktreeBare()
testParseWorktreeMixed()
testParseWorktreeEmpty()
testParseWorktreeWhitespaceOnly()
testParseWorktreeMalformedMissingHead()
testParseWorktreeMalformedMissingPath()
testParseWorktreeNoTrailingNewline()
testBranchNameExtraction()

// GitBranchParser tests
testParseBranchLocal()
testParseBranchRemote()
testParseBranchMultiple()
testParseBranchEmpty()
testParseBranchWhitespaceOnly()
testParseBranchNoDate()
testParseBranchNoUpstream()
testParseBranchCustomRemote()
testParseBranchDetachedHead()
testParseBranchCommitDate()
testParseBranchMalformedLine()
testParseBranchMinimalFields()
testGitBranchInfoDisplayName()
testGitBranchInfoRemoteName()

// GitBranchParser edge case tests
testParseBranchMultipleSlashes()
testParseBranchRemoteMultipleSlashes()
testParseBranchNoRemotesAtAll()
testParseBranchHundreds()
testParseBranchMalformedMixedWithValid()
testParseBranchRemoteWithoutLocal()

// GitBranchInfo boundary tests
testGitBranchInfoDisplayNameDeepNesting()
testGitBranchInfoEquality()
testGitBranchInfoCodableRoundTrip()
testGitBranchInfoLocalWithSlashNotRemote()

// addWorktree command argument tests
testAddWorktreeArgsExistingBranch()
testAddWorktreeArgsExistingRemoteBranch()
testAddWorktreeArgsNewBranchFromHead()
testAddWorktreeArgsNewBranchFromBase()
testAddWorktreeArgsNewBranchFromRemoteBase()
testAddWorktreeArgsBaseBranchIgnoredWhenNotCreating()

// GitStatusParser tests
testParseStatusClean()
testParseStatusDirty()
testParseStatusStagedOnly()
testParseStatusModifiedOnly()
testParseStatusBothStagedAndModified()
testParseStatusUntrackedOnly()
testParseStatusAheadBehind()
testParseStatusNoUpstream()
testParseStatusRenameEntry()
testParseStatusEmpty()
testParseStatusIgnoredEntries()
testGitStatusInfoCleanStatic()
testGitStatusInfoIsDirtyComputed()

printResults()

if failCount > 0 {
    fatalError("Tests failed")
}
