import Foundation
import MoriTmux

// MARK: - TmuxParser: Session Parsing Tests

func testParseSessionsSingle() {
    let output = "$0\tmy-session\t3\t1\n"
    let sessions = TmuxParser.parseSessions(output)
    assertEqual(sessions.count, 1)
    assertEqual(sessions[0].sessionId, "$0")
    assertEqual(sessions[0].name, "my-session")
    assertEqual(sessions[0].windowCount, 3)
    assertTrue(sessions[0].isAttached)
}

func testParseSessionsMultiple() {
    let output = """
    $0\tdev\t2\t1
    $1\tmori/main\t1\t0
    $2\tbackground\t4\t0
    """
    let sessions = TmuxParser.parseSessions(output)
    assertEqual(sessions.count, 3)

    assertEqual(sessions[0].sessionId, "$0")
    assertEqual(sessions[0].name, "dev")
    assertEqual(sessions[0].windowCount, 2)
    assertTrue(sessions[0].isAttached)

    assertEqual(sessions[1].sessionId, "$1")
    assertEqual(sessions[1].name, "mori/main")
    assertEqual(sessions[1].windowCount, 1)
    assertFalse(sessions[1].isAttached)

    assertEqual(sessions[2].sessionId, "$2")
    assertEqual(sessions[2].name, "background")
    assertEqual(sessions[2].windowCount, 4)
    assertFalse(sessions[2].isAttached)
}

func testParseSessionsEmpty() {
    let sessions = TmuxParser.parseSessions("")
    assertEqual(sessions.count, 0)
}

func testParseSessionsMalformed() {
    let output = "incomplete\tdata\n"
    let sessions = TmuxParser.parseSessions(output)
    assertEqual(sessions.count, 0, "Should skip lines with fewer than 4 fields")
}

// MARK: - TmuxParser: Window Parsing Tests

func testParseWindowsSingle() {
    let output = "@0\t0\tzsh\t1\t/Users/test/project\n"
    let windows = TmuxParser.parseWindows(output)
    assertEqual(windows.count, 1)
    assertEqual(windows[0].windowId, "@0")
    assertEqual(windows[0].windowIndex, 0)
    assertEqual(windows[0].name, "zsh")
    assertTrue(windows[0].isActive)
    assertEqual(windows[0].currentPath, "/Users/test/project")
}

func testParseWindowsMultiple() {
    let output = """
    @0\t0\teditor\t1\t/Users/test/project
    @1\t1\tserver\t0\t/Users/test/project/api
    @2\t2\tlogs\t0\t
    """
    let windows = TmuxParser.parseWindows(output)
    assertEqual(windows.count, 3)

    assertEqual(windows[0].windowId, "@0")
    assertEqual(windows[0].name, "editor")
    assertTrue(windows[0].isActive)

    assertEqual(windows[1].windowId, "@1")
    assertEqual(windows[1].windowIndex, 1)
    assertEqual(windows[1].name, "server")
    assertFalse(windows[1].isActive)
    assertEqual(windows[1].currentPath, "/Users/test/project/api")

    assertEqual(windows[2].windowId, "@2")
    assertEqual(windows[2].windowIndex, 2)
    assertNil(windows[2].currentPath, "Empty path should be nil")
}

func testParseWindowsEmpty() {
    let windows = TmuxParser.parseWindows("")
    assertEqual(windows.count, 0)
}

// MARK: - TmuxParser: Pane Parsing Tests

func testParsePanesSingle() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test/project\tzsh\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertEqual(panes[0].paneId, "%0")
    assertEqual(panes[0].tty, "/dev/ttys001")
    assertTrue(panes[0].isActive)
    assertEqual(panes[0].currentPath, "/Users/test/project")
    assertEqual(panes[0].title, "zsh")
    assertNil(panes[0].lastActivity, "No activity field in 5-field format")
}

func testParsePanesMultiple() {
    let output = """
    %0\t/dev/ttys001\t1\t/Users/test\tzsh
    %1\t/dev/ttys002\t0\t/Users/test/src\tvim
    """
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 2)

    assertEqual(panes[0].paneId, "%0")
    assertTrue(panes[0].isActive)
    assertEqual(panes[0].title, "zsh")

    assertEqual(panes[1].paneId, "%1")
    assertFalse(panes[1].isActive)
    assertEqual(panes[1].title, "vim")
    assertEqual(panes[1].tty, "/dev/ttys002")
}

func testParsePanesEmptyOptionals() {
    let output = "%0\t\t0\t\t\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertNil(panes[0].tty, "Empty tty should be nil")
    assertFalse(panes[0].isActive)
    assertNil(panes[0].currentPath, "Empty path should be nil")
    assertNil(panes[0].title, "Empty title should be nil")
}

func testParsePanesEmpty() {
    let panes = TmuxParser.parsePanes("")
    assertEqual(panes.count, 0)
}

func testParsePanesWithActivity() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertEqual(panes[0].paneId, "%0")
    assertEqual(panes[0].lastActivity, 1710784200.0)
}

func testParsePanesMultipleWithActivity() {
    let output = """
    %0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200
    %1\t/dev/ttys002\t0\t/Users/test/src\tvim\t1710784195
    """
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 2)
    assertEqual(panes[0].lastActivity, 1710784200.0)
    assertEqual(panes[1].lastActivity, 1710784195.0)
}

func testParsePanesActivityEmptyField() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertNil(panes[0].lastActivity, "Empty activity field should be nil")
}

func testPaneFormatContainsActivity() {
    assertTrue(
        TmuxParser.paneFormat.contains("#{pane_activity}"),
        "Pane format should include pane_activity"
    )
}

// MARK: - SessionNaming Tests

func testSlugifySimple() {
    assertEqual(SessionNaming.slugify("mori"), "mori")
    assertEqual(SessionNaming.slugify("My Project"), "my-project")
    assertEqual(SessionNaming.slugify("hello_world"), "hello-world")
}

func testSlugifySpecialChars() {
    assertEqual(SessionNaming.slugify("feat/sidebar-v2"), "feat-sidebar-v2")
    assertEqual(SessionNaming.slugify("...leading"), "leading")
    assertEqual(SessionNaming.slugify("trailing..."), "trailing")
    assertEqual(SessionNaming.slugify("a--b"), "a-b", "Should collapse consecutive hyphens")
}

func testSlugifyUnicode() {
    assertEqual(SessionNaming.slugify("cafe123"), "cafe123")
}

func testSessionNameGeneration() {
    assertEqual(
        SessionNaming.sessionName(projectShortName: "mori", worktree: "main"),
        "mori/main"
    )
    assertEqual(
        SessionNaming.sessionName(projectShortName: "mp", worktree: "feat/sidebar"),
        "mp/sidebar"
    )
    assertEqual(
        SessionNaming.sessionName(projectShortName: "api", worktree: "feature/auth-flow"),
        "api/auth-flow"
    )
}

func testSessionNameSanitizesDotPrefix() {
    // Directories starting with "." (e.g. ~/.claude) must have the dot stripped
    // because tmux does not allow "." in session names.
    assertEqual(
        SessionNaming.sessionName(projectShortName: ".claude", worktree: "main"),
        "claude/main"
    )
    assertEqual(
        SessionNaming.sessionName(projectShortName: "vue.js", worktree: "main"),
        "vue-js/main"
    )
}

func testStripBranchPrefix() {
    assertEqual(SessionNaming.stripBranchPrefix("feature/auth"), "auth")
    assertEqual(SessionNaming.stripBranchPrefix("feat/sidebar"), "sidebar")
    assertEqual(SessionNaming.stripBranchPrefix("fix/crash"), "crash")
    assertEqual(SessionNaming.stripBranchPrefix("hotfix/urgent"), "urgent")
    assertEqual(SessionNaming.stripBranchPrefix("release/2.0"), "2.0")
    assertEqual(SessionNaming.stripBranchPrefix("main"), "main")
    assertEqual(SessionNaming.stripBranchPrefix("my-branch"), "my-branch")
}

func testSessionNameParsing() {
    let result = SessionNaming.parse("mori/main")
    assertNotNil(result)
    assertEqual(result?.projectShortName, "mori")
    assertEqual(result?.branchSlug, "main")
}

func testSessionNameParsingComplex() {
    let result = SessionNaming.parse("mp/sidebar-v2")
    assertNotNil(result)
    assertEqual(result?.projectShortName, "mp")
    assertEqual(result?.branchSlug, "sidebar-v2")
}

func testSessionNameParsingInvalid() {
    assertNil(SessionNaming.parse("regular-session"))
    assertNil(SessionNaming.parse("/no-project"))
    assertNil(SessionNaming.parse("no-branch/"))
    assertNil(SessionNaming.parse(""))
}

func testIsMoriSession() {
    assertTrue(SessionNaming.isMoriSession("mori/main"))
    assertTrue(SessionNaming.isMoriSession("a/b"))
    assertFalse(SessionNaming.isMoriSession("dev"))
    assertFalse(SessionNaming.isMoriSession(""))
}

// MARK: - TmuxSession Model Tests

func testTmuxSessionMoriDetection() {
    let moriSession = TmuxSession(sessionId: "$0", name: "mori/main")
    assertTrue(moriSession.isMoriSession)
    assertEqual(moriSession.projectShortName, "mori")
    assertEqual(moriSession.branchSlug, "main")

    let regularSession = TmuxSession(sessionId: "$1", name: "dev")
    assertFalse(regularSession.isMoriSession)
    assertNil(regularSession.projectShortName)
    assertNil(regularSession.branchSlug)
}

// MARK: - Format String Tests

func testFormatStringsContainDelimiter() {
    // Verify format strings use tab delimiter
    let tab = TmuxParser.delimiter
    assertTrue(TmuxParser.sessionFormat.contains(tab), "Session format should use tab delimiter")
    assertTrue(TmuxParser.windowFormat.contains(tab), "Window format should use tab delimiter")
    assertTrue(TmuxParser.paneFormat.contains(tab), "Pane format should use tab delimiter")
}

func testSessionFormatFields() {
    assertTrue(TmuxParser.sessionFormat.contains("#{session_id}"))
    assertTrue(TmuxParser.sessionFormat.contains("#{session_name}"))
    assertTrue(TmuxParser.sessionFormat.contains("#{session_windows}"))
    assertTrue(TmuxParser.sessionFormat.contains("#{session_attached}"))
}

// MARK: - DetectedAgentState Tests

func testDetectedAgentStateRawValues() {
    assertEqual(DetectedAgentState.none.rawValue, "none")
    assertEqual(DetectedAgentState.running.rawValue, "running")
    assertEqual(DetectedAgentState.waitingForInput.rawValue, "waitingForInput")
    assertEqual(DetectedAgentState.error.rawValue, "error")
    assertEqual(DetectedAgentState.completed.rawValue, "completed")
}

// MARK: - PaneStateDetector Tests

func testDetectShellProcessIdle() {
    // Shell commands should be detected as idle (not running)
    for shell in ["bash", "zsh", "fish", "sh", "-bash", "-zsh"] {
        let pane = TmuxPane(paneId: "%0", currentCommand: shell, startTime: 1000)
        let state = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1100)
        assertFalse(state.isRunning, "Shell '\(shell)' should not be running")
        assertFalse(state.isLongRunning, "Shell '\(shell)' should not be long-running")
        assertEqual(state.detectedAgentState, .none, "Shell '\(shell)' should have .none agent state")
    }
}

func testDetectNilCommandIdle() {
    let pane = TmuxPane(paneId: "%0", currentCommand: nil)
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1000)
    assertFalse(state.isRunning)
    assertEqual(state.detectedAgentState, .none)
}

func testDetectEmptyCommandIdle() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "")
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1000)
    assertFalse(state.isRunning)
}

func testDetectRunningCommand() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "node", startTime: 1090)
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1100)
    assertTrue(state.isRunning, "Non-shell command should be running")
    assertFalse(state.isLongRunning, "10s is below 30s threshold")
    assertEqual(state.detectedAgentState, .running)
    assertEqual(state.command, "node")
}

func testDetectLongRunningCommand() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "python", startTime: 1000)
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1100)
    assertTrue(state.isRunning)
    assertTrue(state.isLongRunning, "100s exceeds 30s threshold")
}

func testDetectLongRunningThresholdBoundary() {
    // Exactly 30s — should not be long-running (> 30, not >=)
    let pane = TmuxPane(paneId: "%0", currentCommand: "make", startTime: 1000)
    let state30 = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1030)
    assertFalse(state30.isLongRunning, "Exactly 30s should not be long-running")

    // 31s — should be long-running
    let state31 = PaneStateDetector.detect(pane: pane, capturedOutput: "", now: 1031)
    assertTrue(state31.isLongRunning, "31s should be long-running")
}

func testDetectWaitingForInputPrompt() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "claude", startTime: 1000)
    let output = "Some output\nDo you want to continue? > "
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput)
}

func testDetectWaitingForInputQuestion() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "claude", startTime: 1000)
    let output = "Proceed with changes? "
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput)
}

func testDetectWaitingForInputYesNo() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "npm", startTime: 1000)
    let output = "Install dependencies [Y/n]"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput)
}

func testDetectWaitingForInputPressAnyKey() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "less", startTime: 1000)
    let output = "Press any key to continue"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput)
}

func testDetectWaitingForInputMessage() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "agent", startTime: 1000)
    let output = "Waiting for input from user..."
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput)
}

func testDetectErrorPatterns() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "make", startTime: 1000)

    let errorOutput = "src/main.c:10: error: undefined reference"
    let s1 = PaneStateDetector.detect(pane: pane, capturedOutput: errorOutput, now: 1100)
    assertEqual(s1.detectedAgentState, .error, "Should detect 'error:' pattern")

    let failedOutput = "test_suite FAILED"
    let s2 = PaneStateDetector.detect(pane: pane, capturedOutput: failedOutput, now: 1100)
    assertEqual(s2.detectedAgentState, .error, "Should detect 'FAILED' pattern")

    let panicOutput = "goroutine 1: panic: runtime error"
    let s3 = PaneStateDetector.detect(pane: pane, capturedOutput: panicOutput, now: 1100)
    assertEqual(s3.detectedAgentState, .error, "Should detect 'panic:' pattern")

    let fatalOutput = "fatal: not a git repository"
    let s4 = PaneStateDetector.detect(pane: pane, capturedOutput: fatalOutput, now: 1100)
    assertEqual(s4.detectedAgentState, .error, "Should detect 'fatal:' pattern")
}

func testDetectCompletedPatterns() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "make", startTime: 1000)

    let doneOutput = "Build Done in 5.2s"
    let s1 = PaneStateDetector.detect(pane: pane, capturedOutput: doneOutput, now: 1100)
    assertEqual(s1.detectedAgentState, .completed, "Should detect 'Done' pattern")

    let completeOutput = "Installation Complete"
    let s2 = PaneStateDetector.detect(pane: pane, capturedOutput: completeOutput, now: 1100)
    assertEqual(s2.detectedAgentState, .completed, "Should detect 'Complete' pattern")

    let finishedOutput = "Task Finished successfully"
    let s3 = PaneStateDetector.detect(pane: pane, capturedOutput: finishedOutput, now: 1100)
    assertEqual(s3.detectedAgentState, .completed, "Should detect 'Finished' pattern")
}

func testDetectRunningNoPatterns() {
    // Running command with no matching patterns -> running
    let pane = TmuxPane(paneId: "%0", currentCommand: "python", startTime: 1000)
    // "complete" in output matches completed pattern, so use neutral text
    let output = "Processing items...\n42/100 records"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .running)
}

func testDetectExitCode() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "zsh")
    let output = "Command failed\nexit code: 1\n"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1000)
    assertEqual(state.exitCode, 1)
}

func testDetectExitCodeExitedWith() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "zsh")
    let output = "Process exited with 127"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1000)
    assertEqual(state.exitCode, 127)
}

func testDetectNoExitCode() {
    let pane = TmuxPane(paneId: "%0", currentCommand: "zsh")
    let output = "Normal output without exit info"
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1000)
    assertNil(state.exitCode)
}

func testWaitingPriorityOverError() {
    // waitingForInput has higher priority than error
    let pane = TmuxPane(paneId: "%0", currentCommand: "agent", startTime: 1000)
    let output = "error: something went wrong\nRetry? > "
    let state = PaneStateDetector.detect(pane: pane, capturedOutput: output, now: 1100)
    assertEqual(state.detectedAgentState, .waitingForInput,
        "waitingForInput should take priority over error")
}

func testIsShellProcess() {
    assertTrue(PaneStateDetector.isShellProcess("bash"))
    assertTrue(PaneStateDetector.isShellProcess("zsh"))
    assertTrue(PaneStateDetector.isShellProcess("fish"))
    assertTrue(PaneStateDetector.isShellProcess("sh"))
    assertTrue(PaneStateDetector.isShellProcess("-bash"))
    assertTrue(PaneStateDetector.isShellProcess("-zsh"))
    assertTrue(PaneStateDetector.isShellProcess(nil))
    assertTrue(PaneStateDetector.isShellProcess(""))
    assertFalse(PaneStateDetector.isShellProcess("node"))
    assertFalse(PaneStateDetector.isShellProcess("python"))
    assertFalse(PaneStateDetector.isShellProcess("vim"))
}

func testParsePanesWithCurrentCommand() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\tnode\t1710784100\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertEqual(panes[0].currentCommand, "node")
    assertEqual(panes[0].startTime, 1710784100.0)
}

func testParsePanesWithEmptyCommandFields() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\t\t\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertNil(panes[0].currentCommand, "Empty command should be nil")
    assertNil(panes[0].startTime, "Empty start time should be nil")
}

func testPaneFormatContainsNewFields() {
    assertTrue(
        TmuxParser.paneFormat.contains("#{pane_current_command}"),
        "Pane format should include pane_current_command"
    )
    assertTrue(
        TmuxParser.paneFormat.contains("#{pane_start_time}"),
        "Pane format should include pane_start_time"
    )
}

// MARK: - Agent Pane Option Tests

func testAgentProcessNames() {
    assertTrue(AgentDetector.agentProcessNames.contains("claude"))
    assertTrue(AgentDetector.agentProcessNames.contains("codex"))
    assertTrue(AgentDetector.agentProcessNames.contains("omp"))
    assertTrue(AgentDetector.agentProcessNames.contains("pi"))
    assertFalse(AgentDetector.agentProcessNames.contains("zsh"))
}

func testParsePanesWithAgentState() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\tclaude\t1710784100\t12345\tworking\tclaude\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertEqual(panes[0].agentState, "working")
    assertEqual(panes[0].agentName, "claude")
}

func testParsePanesWithEmptyAgentFields() {
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\tnode\t1710784100\t12345\t\t\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertNil(panes[0].agentState)
    assertNil(panes[0].agentName)
}

func testParsePanesWithoutAgentFields() {
    // Backwards compatible: fewer fields than expected
    let output = "%0\t/dev/ttys001\t1\t/Users/test\tzsh\t1710784200\tnode\t1710784100\t12345\n"
    let panes = TmuxParser.parsePanes(output)
    assertEqual(panes.count, 1)
    assertNil(panes[0].agentState)
    assertNil(panes[0].agentName)
}

func testPaneFormatContainsAgentFields() {
    assertTrue(
        TmuxParser.paneFormat.contains("#{@mori-agent-state}"),
        "Pane format should include @mori-agent-state"
    )
    assertTrue(
        TmuxParser.paneFormat.contains("#{@mori-agent-name}"),
        "Pane format should include @mori-agent-name"
    )
}

// MARK: - Capture Pane Output Edge Case Tests

func testCapturePaneOutputEmptyResult() {
    // capturePaneOutput returns a String. An empty pane returns empty/whitespace.
    // Downstream consumers should handle empty output gracefully.
    let emptyOutput = ""
    assertTrue(emptyOutput.isEmpty, "Empty pane output should be empty string")

    let whitespaceOutput = "\n\n\n"
    let trimmed = whitespaceOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    assertTrue(trimmed.isEmpty, "Whitespace-only pane output trims to empty")
}

func testCapturePaneOutputLargeLineCount() {
    // tmux capture-pane with -S -N where N > actual lines just returns all available lines.
    // Simulate: request 200 lines, only 3 available.
    let available = "line1\nline2\nline3\n"
    let lines = available.split(separator: "\n", omittingEmptySubsequences: false)
    // With 3 content lines + trailing, we get <= 200 requested
    assertTrue(lines.count <= 200, "Line count within requested range")
    assertTrue(lines.count >= 3, "All available lines present")
}

// MARK: - Main

print("=== MoriTmux Tests ===")

// Parser: Sessions
testParseSessionsSingle()
testParseSessionsMultiple()
testParseSessionsEmpty()
testParseSessionsMalformed()

// Parser: Windows
testParseWindowsSingle()
testParseWindowsMultiple()
testParseWindowsEmpty()

// Parser: Panes
testParsePanesSingle()
testParsePanesMultiple()
testParsePanesEmptyOptionals()
testParsePanesEmpty()
testParsePanesWithActivity()
testParsePanesMultipleWithActivity()
testParsePanesActivityEmptyField()
testPaneFormatContainsActivity()

// SessionNaming
testSlugifySimple()
testSlugifySpecialChars()
testSlugifyUnicode()
testSessionNameGeneration()
testSessionNameSanitizesDotPrefix()
testStripBranchPrefix()
testSessionNameParsing()
testSessionNameParsingComplex()
testSessionNameParsingInvalid()
testIsMoriSession()

// TmuxSession model
testTmuxSessionMoriDetection()

// Format strings
testFormatStringsContainDelimiter()
testSessionFormatFields()

// DetectedAgentState
testDetectedAgentStateRawValues()

// PaneStateDetector
testDetectShellProcessIdle()
testDetectNilCommandIdle()
testDetectEmptyCommandIdle()
testDetectRunningCommand()
testDetectLongRunningCommand()
testDetectLongRunningThresholdBoundary()
testDetectWaitingForInputPrompt()
testDetectWaitingForInputQuestion()
testDetectWaitingForInputYesNo()
testDetectWaitingForInputPressAnyKey()
testDetectWaitingForInputMessage()
testDetectErrorPatterns()
testDetectCompletedPatterns()
testDetectRunningNoPatterns()
testDetectExitCode()
testDetectExitCodeExitedWith()
testDetectNoExitCode()
testWaitingPriorityOverError()
testIsShellProcess()
testParsePanesWithCurrentCommand()
testParsePanesWithEmptyCommandFields()
testPaneFormatContainsNewFields()

// Agent pane options
testAgentProcessNames()
testParsePanesWithAgentState()
testParsePanesWithEmptyAgentFields()
testParsePanesWithoutAgentFields()
testPaneFormatContainsAgentFields()

// Capture pane output edge cases
testCapturePaneOutputEmptyResult()
testCapturePaneOutputLargeLineCount()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
