import Foundation
import MoriCore

func testSSHControlSocketPathLengthLimit() {
    let longTemp = "/var/folders/" + String(repeating: "very-long-segment/", count: 12)
    let path = SSHCommandSupport.controlSocketPath(endpointKey: "momo@example.com:2222", temporaryDirectory: longTemp)
    assertTrue(path.utf8.count < 100, "Control socket path must remain below Unix socket limits")
    assertTrue(path.hasSuffix(".sock"), "Control socket path should preserve .sock suffix")
}

func testSSHExecutionConfigTargetFormatting() {
    let withUser = SSHExecutionConfig(host: "example.com", user: "momo", port: 22)
    let withoutUser = SSHExecutionConfig(host: "example.com")
    assertEqual(withUser.target, "momo@example.com")
    assertEqual(withoutUser.target, "example.com")
}

func testSSHRemovingBatchMode() {
    let input = [
        "-o", "BatchMode=yes",
        "-o", "ControlMaster=auto",
        "-o", "BatchMode=no",
        "-o", "ServerAliveInterval=5",
    ]
    let result = SSHCommandSupport.removingBatchMode(from: input)
    assertEqual(result, [
        "-o", "ControlMaster=auto",
        "-o", "ServerAliveInterval=5",
    ])
}

func testSSHShellEscape() {
    assertEqual(SSHCommandSupport.shellEscape(""), "''")
    assertEqual(SSHCommandSupport.shellEscape("abc"), "'abc'")
    assertEqual(SSHCommandSupport.shellEscape("a'b"), "'a'\"'\"'b'")
}

func testSSHAskPassEnvironmentIsMinimal() {
    let env = SSHCommandSupport.askPassEnvironment(
        scriptPath: "/tmp/script.sh",
        baseEnvironment: [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "TMPDIR": "/tmp",
            "LANG": "en_US.UTF-8",
            "SECRET": "should-not-leak",
            "MORI_SSH_PASSWORD": "bad",
        ]
    )
    assertEqual(env["SSH_ASKPASS"], "/tmp/script.sh")
    assertEqual(env["SSH_ASKPASS_REQUIRE"], "force")
    assertEqual(env["DISPLAY"], "mori")
    assertEqual(env["PATH"], "/usr/bin")
    assertNil(env["SECRET"])
    assertNil(env["MORI_SSH_PASSWORD"])
}

func testSSHCreateAskPassScriptHasSecurePermissions() {
    let script: SSHAskPassScript
    do {
        script = try SSHCommandSupport.createAskPassScript(password: "pa'ss")
    } catch {
        assertTrue(false, "Failed to create askpass script: \(error.localizedDescription)")
        return
    }
    defer { script.cleanup() }

    let attrs = try? FileManager.default.attributesOfItem(atPath: script.path)
    let mode = (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    assertEqual(mode & 0o777, 0o700, "Askpass script should be executable only by current user")
}

func testSSHRemoteLoginShellCommand() {
    let command = SSHCommandSupport.remoteLoginShellCommand(
        "tmux -V",
        environment: [
            "TERM_PROGRAM": "ghostty",
            "STARSHIP_LOG": "error",
        ]
    )
    assertTrue(command.contains("exec ${SHELL:-/bin/sh} -l -c 'tmux -V'"))
    assertTrue(command.contains("export STARSHIP_LOG='error';"))
    assertTrue(command.contains("export TERM_PROGRAM='ghostty';"))
}
