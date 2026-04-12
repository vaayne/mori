import Foundation
@testable import MoriIPC

// MARK: - IPCCommand Round-trip Tests

func testCommandProjectListRoundTrip() {
    let cmd = IPCCommand.projectList
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "projectList round-trip")
}

func testCommandWorktreeCreateRoundTrip() {
    let cmd = IPCCommand.worktreeCreate(project: "mori", branch: "feature/ipc")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "worktreeCreate round-trip")
}

func testCommandFocusRoundTrip() {
    let cmd = IPCCommand.focus(project: "mori", worktree: "main")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "focus round-trip")
}

func testCommandSendRoundTrip() {
    let cmd = IPCCommand.send(project: "mori", worktree: "main", window: "shell", keys: "ls -la\n")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "send round-trip")
}

func testCommandNewWindowRoundTrip() {
    let cmd = IPCCommand.newWindow(project: "mori", worktree: "main", name: "logs")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "newWindow round-trip")
}

func testCommandNewWindowNilNameRoundTrip() {
    let cmd = IPCCommand.newWindow(project: "mori", worktree: "main", name: nil)
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "newWindow nil name round-trip")
}

func testCommandOpenRoundTrip() {
    let cmd = IPCCommand.open(path: "/Users/test/projects/mori")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "open round-trip")
}

func testCommandSetWorkflowStatusRoundTrip() {
    let cmd = IPCCommand.setWorkflowStatus(project: "mori", worktree: "feature-branch", status: "inProgress")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "setWorkflowStatus round-trip")
}

func testCommandSetWorkflowStatusAllStatuses() {
    let statuses = ["todo", "inProgress", "needsReview", "done", "cancelled"]
    for status in statuses {
        let cmd = IPCCommand.setWorkflowStatus(project: "proj", worktree: "wt", status: status)
        let data = try! JSONEncoder().encode(cmd)
        let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
        assertEqual(decoded, cmd, "setWorkflowStatus round-trip for \(status)")
    }
}

func testCommandSetWorkflowStatusFraming() {
    let cmd = IPCCommand.setWorkflowStatus(project: "mori", worktree: "main", status: "done")
    let request = IPCRequest(command: cmd, requestId: "status-1")
    let data = try! IPCFraming.encode(request)
    assertEqual(data.last, 0x0A, "setWorkflowStatus framed request ends with newline")
    let decoded = try! IPCFraming.decodeRequest(from: data)
    assertEqual(decoded.command, cmd, "setWorkflowStatus framed request decodable")
    assertEqual(decoded.requestId, "status-1", "setWorkflowStatus framed request id")
}

// MARK: - Pane Command Round-trip Tests

func testCommandPaneListRoundTrip() {
    let cmd = IPCCommand.paneList()
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "paneList round-trip")
}

func testCommandPaneListWithFiltersRoundTrip() {
    let cmd = IPCCommand.paneList(project: "mori", worktree: "main")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "paneList filtered round-trip")
}

func testCommandPaneReadRoundTrip() {
    let cmd = IPCCommand.paneRead(project: "mori", worktree: "main", window: "shell", lines: 50)
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "paneRead round-trip")
}

func testCommandPaneReadMaxLines() {
    let cmd = IPCCommand.paneRead(project: "mori", worktree: "feat", window: "agent", lines: 200)
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "paneRead max lines round-trip")
}

func testCommandPaneListFraming() {
    let cmd = IPCCommand.paneList()
    let request = IPCRequest(command: cmd, requestId: "pane-1")
    let data = try! IPCFraming.encode(request)
    assertEqual(data.last, 0x0A, "paneList framed request ends with newline")
    let decoded = try! IPCFraming.decodeRequest(from: data)
    assertEqual(decoded.command, cmd, "paneList framed request decodable")
    assertEqual(decoded.requestId, "pane-1", "paneList framed request id")
}

func testCommandPaneReadFraming() {
    let cmd = IPCCommand.paneRead(project: "proj", worktree: "wt", window: "win", lines: 30)
    let request = IPCRequest(command: cmd, requestId: "pane-2")
    let data = try! IPCFraming.encode(request)
    assertEqual(data.last, 0x0A, "paneRead framed request ends with newline")
    let decoded = try! IPCFraming.decodeRequest(from: data)
    assertEqual(decoded.command, cmd, "paneRead framed request decodable")
    assertEqual(decoded.requestId, "pane-2", "paneRead framed request id")
}

func testCommandPaneMessageRoundTrip() {
    let cmd = IPCCommand.paneMessage(project: "mori", worktree: "main", window: "codex", text: "Review auth module")
    let data = try! JSONEncoder().encode(cmd)
    let decoded = try! JSONDecoder().decode(IPCCommand.self, from: data)
    assertEqual(decoded, cmd, "paneMessage round-trip")
}

func testCommandPaneMessageFraming() {
    let cmd = IPCCommand.paneMessage(project: "api", worktree: "feat", window: "claude", text: "hello")
    let request = IPCRequest(command: cmd, requestId: "msg-1")
    let data = try! IPCFraming.encode(request)
    assertEqual(data.last, 0x0A, "paneMessage framed request ends with newline")
    let decoded = try! IPCFraming.decodeRequest(from: data)
    assertEqual(decoded.command, cmd, "paneMessage framed request decodable")
    assertEqual(decoded.requestId, "msg-1", "paneMessage framed request id")
}

// MARK: - IPCRequest Tests

func testIPCRequestRoundTrip() {
    let request = IPCRequest(
        command: .focus(project: "mori", worktree: "main"),
        requestId: "req-123"
    )
    let data = try! JSONEncoder().encode(request)
    let decoded = try! JSONDecoder().decode(IPCRequest.self, from: data)
    assertEqual(decoded.command, request.command, "request command")
    assertEqual(decoded.requestId, "req-123", "request id")
}

func testIPCRequestNilId() {
    let request = IPCRequest(command: .projectList)
    let data = try! JSONEncoder().encode(request)
    let decoded = try! JSONDecoder().decode(IPCRequest.self, from: data)
    assertEqual(decoded.command, .projectList, "command preserved")
    assertNil(decoded.requestId, "nil request id preserved")
}

// MARK: - IPCResponse Tests

func testIPCResponseSuccessWithPayload() {
    let payload = Data("{\"name\":\"mori\"}".utf8)
    let response = IPCResponse.success(payload: payload)
    let data = try! JSONEncoder().encode(response)
    let decoded = try! JSONDecoder().decode(IPCResponse.self, from: data)
    assertEqual(decoded, response, "success with payload round-trip")
}

func testIPCResponseSuccessNilPayload() {
    let response = IPCResponse.success(payload: nil)
    let data = try! JSONEncoder().encode(response)
    let decoded = try! JSONDecoder().decode(IPCResponse.self, from: data)
    assertEqual(decoded, response, "success nil payload round-trip")
}

func testIPCResponseError() {
    let response = IPCResponse.error(message: "Project not found")
    let data = try! JSONEncoder().encode(response)
    let decoded = try! JSONDecoder().decode(IPCResponse.self, from: data)
    assertEqual(decoded, response, "error round-trip")
}

// MARK: - IPCResponseEnvelope Tests

func testResponseEnvelopeRoundTrip() {
    let envelope = IPCResponseEnvelope(
        response: .success(payload: Data("[]".utf8)),
        requestId: "req-456"
    )
    let data = try! JSONEncoder().encode(envelope)
    let decoded = try! JSONDecoder().decode(IPCResponseEnvelope.self, from: data)
    assertEqual(decoded.response, envelope.response, "envelope response")
    assertEqual(decoded.requestId, "req-456", "envelope request id")
}

func testResponseEnvelopeNilId() {
    let envelope = IPCResponseEnvelope(
        response: .error(message: "timeout"),
        requestId: nil
    )
    let data = try! JSONEncoder().encode(envelope)
    let decoded = try! JSONDecoder().decode(IPCResponseEnvelope.self, from: data)
    assertEqual(decoded.response, envelope.response, "error envelope")
    assertNil(decoded.requestId, "nil request id in envelope")
}

// MARK: - IPCFraming Tests

func testFramingEncodeRequest() {
    let request = IPCRequest(command: .projectList, requestId: "r1")
    let data = try! IPCFraming.encode(request)
    // Should end with newline
    assertEqual(data.last, 0x0A, "request ends with newline")
    // Should be valid JSON (minus trailing newline)
    let jsonData = data.dropLast()
    let decoded = try! JSONDecoder().decode(IPCRequest.self, from: Data(jsonData))
    assertEqual(decoded.command, .projectList, "framed request decodable")
}

func testFramingEncodeResponseEnvelope() {
    let envelope = IPCResponseEnvelope(response: .success(payload: nil), requestId: "r2")
    let data = try! IPCFraming.encode(envelope)
    assertEqual(data.last, 0x0A, "envelope ends with newline")
    let jsonData = data.dropLast()
    let decoded = try! JSONDecoder().decode(IPCResponseEnvelope.self, from: Data(jsonData))
    assertEqual(decoded.requestId, "r2", "framed envelope decodable")
}

func testFramingDecodeRequest() {
    let json = """
    {"command":{"projectList":{}},"requestId":"test-1"}
    """
    let data = Data(json.utf8)
    let request = try! IPCFraming.decodeRequest(from: data)
    assertEqual(request.command, .projectList, "decode request from raw JSON")
    assertEqual(request.requestId, "test-1", "request id from raw JSON")
}

func testFramingDecodeRequestWithTrailingNewline() {
    let request = IPCRequest(command: .open(path: "/tmp"), requestId: "r3")
    let encoded = try! IPCFraming.encode(request) // has trailing newline
    let decoded = try! IPCFraming.decodeRequest(from: encoded)
    assertEqual(decoded.command, .open(path: "/tmp"), "decode tolerates trailing newline")
}

func testSplitMessagesSingleComplete() {
    let msg = Data("hello\n".utf8)
    let (messages, remainder) = IPCFraming.splitMessages(msg)
    assertEqual(messages.count, 1, "one message")
    assertEqual(String(data: messages[0], encoding: .utf8), "hello", "message content")
    assertTrue(remainder.isEmpty, "no remainder")
}

func testSplitMessagesMultiple() {
    let msg = Data("first\nsecond\n".utf8)
    let (messages, remainder) = IPCFraming.splitMessages(msg)
    assertEqual(messages.count, 2, "two messages")
    assertEqual(String(data: messages[0], encoding: .utf8), "first", "first message")
    assertEqual(String(data: messages[1], encoding: .utf8), "second", "second message")
    assertTrue(remainder.isEmpty, "no remainder")
}

func testSplitMessagesIncomplete() {
    let msg = Data("complete\nincomple".utf8)
    let (messages, remainder) = IPCFraming.splitMessages(msg)
    assertEqual(messages.count, 1, "one complete message")
    assertEqual(String(data: messages[0], encoding: .utf8), "complete", "complete message")
    assertEqual(String(data: remainder, encoding: .utf8), "incomple", "remainder preserved")
}

func testSplitMessagesEmpty() {
    let (messages, remainder) = IPCFraming.splitMessages(Data())
    assertTrue(messages.isEmpty, "no messages from empty data")
    assertTrue(remainder.isEmpty, "no remainder from empty data")
}

func testSplitMessagesNoNewline() {
    let msg = Data("partial".utf8)
    let (messages, remainder) = IPCFraming.splitMessages(msg)
    assertTrue(messages.isEmpty, "no complete messages")
    assertEqual(String(data: remainder, encoding: .utf8), "partial", "all is remainder")
}

// MARK: - MoriPaths Tests

func testMoriPathsSocketPathEnvOverride() {
    setenv("MORI_SOCKET_PATH", "/tmp/custom.sock", 1)
    defer { unsetenv("MORI_SOCKET_PATH") }
    assertEqual(MoriPaths.socketPath, "/tmp/custom.sock", "MORI_SOCKET_PATH overrides socket path")
}

func testMoriPathsAppSupportDirEnvOverride() {
    setenv("MORI_APP_SUPPORT_DIR", "/tmp/mori-test", 1)
    defer { unsetenv("MORI_APP_SUPPORT_DIR") }
    assertEqual(MoriPaths.appSupportDirectory.path, "/tmp/mori-test", "MORI_APP_SUPPORT_DIR overrides app support dir")
}

func testMoriPathsDefaultSocketPathEndsWithSock() {
    let path = MoriPaths.socketPath
    assertTrue(path.hasSuffix("mori.sock"), "default socket path ends with mori.sock, got: \(path)")
}

func testMoriPathsIsInAppBundlePrimaryExecutable() {
    // Simulates: /Applications/Mori.app/Contents/MacOS/Mori
    let path = "/Applications/Mori.app/Contents/MacOS/Mori"
    assertTrue(MoriPaths.isInAppBundle(path), "primary executable inside .app bundle should be detected")
}

func testMoriPathsIsInAppBundleSecondaryExecutable() {
    // Simulates: /Applications/Mori.app/Contents/MacOS/bin/mori
    // This is the bug scenario — the CLI binary inside the .app bundle
    let path = "/Applications/Mori.app/Contents/MacOS/bin/mori"
    assertTrue(MoriPaths.isInAppBundle(path), "CLI binary inside .app bundle should be detected")
}

func testMoriPathsIsInAppBundleStandaloneBinary() {
    // No .app ancestor — dev build or standalone CLI
    let path = "/Users/dev/.build-cli/release/mori"
    assertFalse(MoriPaths.isInAppBundle(path), "standalone dev build should NOT be detected as bundled")
}

func testMoriPathsIsInAppBundleSymlinkResolved() {
    // After symlink resolution, path inside .app should be detected
    let path = "/Applications/Mori.app/Contents/MacOS/bin/mori"
    assertTrue(MoriPaths.isInAppBundle(path), "resolved symlink inside .app should be detected")
}

func testMoriPathsIsInAppBundleBuildDirectory() {
    // Even if path contains .app but is inside a build directory
    let path = "/Users/dev/mori/.build-cli/release/Mori.app/Contents/MacOS/Mori"
    assertFalse(MoriPaths.isInAppBundle(path), ".build-cli path should NOT be detected as bundled")
}

func testMoriPathsIsInAppBundleDerivedData() {
    let path = "/Users/dev/DerivedData/Mori-abc/Mori.app/Contents/MacOS/Mori"
    assertFalse(MoriPaths.isInAppBundle(path), "DerivedData path should NOT be detected as bundled")
}

func testMoriPathsIsInBuildDirectory() {
    assertTrue(MoriPaths.isInBuildDirectory("/Users/dev/mori/.build/release/Mori"), "detects .build")
    assertTrue(MoriPaths.isInBuildDirectory("/Users/dev/mori/.build-cli/release/mori"), "detects .build-cli")
    assertTrue(MoriPaths.isInBuildDirectory("/Users/dev/Library/Developer/Xcode/DerivedData/Mori-xyz"), "detects DerivedData")
    assertFalse(MoriPaths.isInBuildDirectory("/Users/DerivedDataUser/mori"), "no false positive on user path with DerivedData")
    assertFalse(MoriPaths.isInBuildDirectory("/Applications/Mori.app"), "no false positive on .app bundle")
}

// MARK: - Run All Tests

print("Running MoriIPC tests...")

// Command round-trips
testCommandProjectListRoundTrip()
testCommandWorktreeCreateRoundTrip()
testCommandFocusRoundTrip()
testCommandSendRoundTrip()
testCommandNewWindowRoundTrip()
testCommandNewWindowNilNameRoundTrip()
testCommandOpenRoundTrip()
testCommandSetWorkflowStatusRoundTrip()
testCommandSetWorkflowStatusAllStatuses()
testCommandSetWorkflowStatusFraming()

// Pane command round-trips
testCommandPaneListRoundTrip()
    testCommandPaneListWithFiltersRoundTrip()
testCommandPaneReadRoundTrip()
testCommandPaneReadMaxLines()
testCommandPaneListFraming()
testCommandPaneReadFraming()
testCommandPaneMessageRoundTrip()
testCommandPaneMessageFraming()

// Request round-trips
testIPCRequestRoundTrip()
testIPCRequestNilId()

// Response round-trips
testIPCResponseSuccessWithPayload()
testIPCResponseSuccessNilPayload()
testIPCResponseError()

// Envelope round-trips
testResponseEnvelopeRoundTrip()
testResponseEnvelopeNilId()

// Framing
testFramingEncodeRequest()
testFramingEncodeResponseEnvelope()
testFramingDecodeRequest()
testFramingDecodeRequestWithTrailingNewline()
testSplitMessagesSingleComplete()
testSplitMessagesMultiple()
testSplitMessagesIncomplete()
testSplitMessagesEmpty()
testSplitMessagesNoNewline()

// MoriPaths
testMoriPathsSocketPathEnvOverride()
testMoriPathsAppSupportDirEnvOverride()
testMoriPathsDefaultSocketPathEndsWithSock()
testMoriPathsIsInAppBundlePrimaryExecutable()
testMoriPathsIsInAppBundleSecondaryExecutable()
testMoriPathsIsInAppBundleStandaloneBinary()
testMoriPathsIsInAppBundleSymlinkResolved()
testMoriPathsIsInAppBundleBuildDirectory()
testMoriPathsIsInAppBundleDerivedData()
testMoriPathsIsInBuildDirectory()

printResults()

if failCount > 0 {
    exit(1)
}
