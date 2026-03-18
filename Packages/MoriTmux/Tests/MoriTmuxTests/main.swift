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
    $1\tws::mori::main\t1\t0
    $2\tbackground\t4\t0
    """
    let sessions = TmuxParser.parseSessions(output)
    assertEqual(sessions.count, 3)

    assertEqual(sessions[0].sessionId, "$0")
    assertEqual(sessions[0].name, "dev")
    assertEqual(sessions[0].windowCount, 2)
    assertTrue(sessions[0].isAttached)

    assertEqual(sessions[1].sessionId, "$1")
    assertEqual(sessions[1].name, "ws::mori::main")
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
        SessionNaming.sessionName(project: "Mori", worktree: "main"),
        "ws::mori::main"
    )
    assertEqual(
        SessionNaming.sessionName(project: "My Project", worktree: "feat/sidebar"),
        "ws::my-project::feat-sidebar"
    )
}

func testSessionNameParsing() {
    let result = SessionNaming.parse("ws::mori::main")
    assertNotNil(result)
    assertEqual(result?.projectSlug, "mori")
    assertEqual(result?.worktreeSlug, "main")
}

func testSessionNameParsingComplex() {
    let result = SessionNaming.parse("ws::my-project::feat-sidebar")
    assertNotNil(result)
    assertEqual(result?.projectSlug, "my-project")
    assertEqual(result?.worktreeSlug, "feat-sidebar")
}

func testSessionNameParsingInvalid() {
    assertNil(SessionNaming.parse("regular-session"))
    assertNil(SessionNaming.parse("ws::only-one-part"))
    assertNil(SessionNaming.parse(""))
}

func testIsMoriSession() {
    assertTrue(SessionNaming.isMoriSession("ws::mori::main"))
    assertTrue(SessionNaming.isMoriSession("ws::a::b"))
    assertFalse(SessionNaming.isMoriSession("dev"))
    assertFalse(SessionNaming.isMoriSession(""))
}

// MARK: - TmuxSession Model Tests

func testTmuxSessionMoriDetection() {
    let moriSession = TmuxSession(sessionId: "$0", name: "ws::mori::main")
    assertTrue(moriSession.isMoriSession)
    assertEqual(moriSession.projectSlug, "mori")
    assertEqual(moriSession.worktreeSlug, "main")

    let regularSession = TmuxSession(sessionId: "$1", name: "dev")
    assertFalse(regularSession.isMoriSession)
    assertNil(regularSession.projectSlug)
    assertNil(regularSession.worktreeSlug)
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

// SessionNaming
testSlugifySimple()
testSlugifySpecialChars()
testSlugifyUnicode()
testSessionNameGeneration()
testSessionNameParsing()
testSessionNameParsingComplex()
testSessionNameParsingInvalid()
testIsMoriSession()

// TmuxSession model
testTmuxSessionMoriDetection()

// Format strings
testFormatStringsContainDelimiter()
testSessionFormatFields()

printResults()

if failCount > 0 {
    fatalError("Tests failed")
}
