#if os(macOS)
import AppKit
@testable import MoriTerminal

private var failures = 0

@MainActor
private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        failures += 1
        print("FAIL: \(message) — expected \(expected), got \(actual)")
    }
}

@MainActor
private func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

private func makePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: .init("com.vaayne.mori.tests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
}

private func stringItem(_ value: String) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setString(value, forType: .string)
    return item
}

private func fileURLItem(_ value: String) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setString(value, forType: .fileURL)
    return item
}

@MainActor
private func testSurfaceRegistersDropTypes() {
    let view = GhosttySurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let registeredTypes = Set(view.registeredDraggedTypes)
    assertTrue(registeredTypes.contains(.fileURL), "terminal surface registers file URL drops")
    assertTrue(registeredTypes.contains(.URL), "terminal surface registers URL drops")
    assertTrue(registeredTypes.contains(.string), "terminal surface registers string drops")
}

@MainActor
private func testURLDropEscapesValue() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("https://example.com/?one=1&two=2", forType: .URL)
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        #"https://example.com/\?one=1\&two=2"#,
        "URL drops are shell-escaped"
    )
}

@MainActor
private func testStringDrop() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([stringItem("https://example.com/page")])
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        "https://example.com/page",
        "plain strings are preserved"
    )
}

@MainActor
private func testFileDropEscapesPath() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([
        fileURLItem("file:///Users/test/my%20file%20(1).png"),
    ])
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        #"/Users/test/my\ file\ \(1\).png"#,
        "file URLs become shell-escaped absolute paths"
    )
}

@MainActor
private func testMultipleFileDropPreservesOrder() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([
        fileURLItem("file:///Users/test/a.png"),
        fileURLItem("file:///Users/test/b.png"),
    ])
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        "/Users/test/a.png /Users/test/b.png",
        "multiple dropped files are joined in order"
    )
}

@MainActor
private func testFileDropIgnoresStringItems() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([
        fileURLItem("file:///Users/test/image.png"),
        stringItem("describe this"),
    ])
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        "/Users/test/image.png",
        "file URLs win over plain strings, matching Ghostty's drag precedence"
    )
}

@MainActor
private func testFileDropRejectsLineBreaksInPath() {
    for (name, encoded) in [("newline", "%0A"), ("carriage return", "%0D")] {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([
            fileURLItem("file:///Users/test/evil\(encoded)rm%20-rf%20~.png"),
        ])
        assertEqual(
            pasteboard.moriTerminalStringContents(),
            nil,
            "file paths containing a \(name) are rejected instead of inserted"
        )
    }
}

@MainActor
private func testFileDropRejectsWholeDropOnUnsafePath() {
    let pasteboard = makePasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([
        fileURLItem("file:///Users/test/safe.png"),
        fileURLItem("file:///Users/test/evil%0Arm%20-rf%20~.png"),
    ])
    assertEqual(
        pasteboard.moriTerminalStringContents(),
        nil,
        "one unsafe path rejects the whole drop rather than silently dropping a file"
    )
}

@MainActor
private func runTests() {
    testSurfaceRegistersDropTypes()
    testURLDropEscapesValue()
    testStringDrop()
    testFileDropEscapesPath()
    testMultipleFileDropPreservesOrder()
    testFileDropIgnoresStringItems()
    testFileDropRejectsLineBreaksInPath()
    testFileDropRejectsWholeDropOnUnsafePath()

    if failures == 0 {
        print("MoriTerminalTests passed")
    } else {
        print("MoriTerminalTests failed: \(failures)")
        fatalError("Tests failed")
    }
}

runTests()
#endif
