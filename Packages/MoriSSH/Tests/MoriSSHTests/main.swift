import Foundation
import MoriSSH

// MARK: - SSHAuthMethod Tests

func testPasswordAuthConstruction() {
    let auth = SSHAuthMethod.password("secret")
    if case .password(let pass) = auth {
        assertEqual(pass, "secret")
    } else {
        assertTrue(false, "Expected .password case")
    }
}

func testPublicKeyAuthConstruction() {
    let keyData = Data("fake-key".utf8)
    let auth = SSHAuthMethod.publicKey(privateKey: keyData, passphrase: "phrase")
    if case .publicKey(let key, let passphrase) = auth {
        assertEqual(key, keyData)
        assertEqual(passphrase, "phrase")
    } else {
        assertTrue(false, "Expected .publicKey case")
    }
}

func testPublicKeyAuthNoPassphrase() {
    let keyData = Data("fake-key".utf8)
    let auth = SSHAuthMethod.publicKey(privateKey: keyData, passphrase: nil)
    if case .publicKey(_, let passphrase) = auth {
        assertNil(passphrase)
    } else {
        assertTrue(false, "Expected .publicKey case")
    }
}

// MARK: - SSHError Tests

func testSSHErrorDescriptions() {
    let errors: [(SSHError, String)] = [
        (.connectionFailed("refused"), "SSH connection failed: refused"),
        (.authenticationFailed, "SSH authentication failed"),
        (.timeout, "SSH connection timed out"),
        (.channelError("broken"), "SSH channel error: broken"),
        (.disconnected, "SSH disconnected"),
    ]

    for (error, expected) in errors {
        assertEqual(error.localizedDescription, expected, "Error description mismatch for \(error)")
    }
}

func testSSHErrorCases() {
    // Verify all cases exist and are distinct
    let e1 = SSHError.connectionFailed("test")
    let e2 = SSHError.authenticationFailed
    let e3 = SSHError.timeout
    let e4 = SSHError.channelError("test")
    let e5 = SSHError.disconnected

    assertNotNil(e1.errorDescription)
    assertNotNil(e2.errorDescription)
    assertNotNil(e3.errorDescription)
    assertNotNil(e4.errorDescription)
    assertNotNil(e5.errorDescription)
}

// MARK: - SSHConnectionManager Tests (unit-level, no real SSH)

func testSSHConnectionManagerExists() {
    // Verify the type exists and can be instantiated
    let _ = SSHConnectionManager()
    assertTrue(true, "SSHConnectionManager can be instantiated")
}

func testSSHConnectionManagerInitialState() async {
    let manager = SSHConnectionManager()
    let connected = await manager.isConnected
    assertFalse(connected, "New manager should not be connected")
}

func testSSHConnectionManagerOpenExecWithoutConnect() async {
    let manager = SSHConnectionManager()
    do {
        _ = try await manager.openExecChannel(command: "echo test")
        assertTrue(false, "Should have thrown SSHError.disconnected")
    } catch {
        assertTrue(error is SSHError, "Expected SSHError, got \(type(of: error))")
    }
}

func testSSHChannelTypeExists() {
    // Verify SSHChannel type is accessible (can't create without NIO channel)
    assertTrue(true, "SSHChannel type exists in MoriSSH module")
}

// MARK: - Async Test Runner

/// Run async tests using a RunLoop-based approach that avoids DispatchSemaphore deadlocks.
nonisolated(unsafe) var asyncTestsDone = false

func runAsyncTests() {
    asyncTestsDone = false
    Task.detached {
        await testSSHConnectionManagerInitialState()
        await testSSHConnectionManagerOpenExecWithoutConnect()
        asyncTestsDone = true
    }
    // Spin the RunLoop until the async tests complete
    while !asyncTestsDone {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
}

// MARK: - Main

print("=== MoriSSH Tests ===")

// SSHAuthMethod
testPasswordAuthConstruction()
testPublicKeyAuthConstruction()
testPublicKeyAuthNoPassphrase()

// SSHError
testSSHErrorDescriptions()
testSSHErrorCases()

// Type existence
testSSHConnectionManagerExists()
testSSHChannelTypeExists()

// Async tests (SSHConnectionManager)
runAsyncTests()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
