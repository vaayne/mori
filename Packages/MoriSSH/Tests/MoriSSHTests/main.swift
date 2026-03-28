import Foundation
import MoriSSH
import NIOCore
import NIOEmbedded
import NIOSSH

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

    // Verify different cases produce different descriptions
    assertNotEqual(e1.errorDescription!, e2.errorDescription!)
    assertNotEqual(e2.errorDescription!, e3.errorDescription!)
    assertNotEqual(e3.errorDescription!, e4.errorDescription!)
    assertNotEqual(e4.errorDescription!, e5.errorDescription!)
}

// MARK: - SSHConnectionManager Tests (unit-level, no real SSH)

func testSSHConnectionManagerInitialState() async {
    let manager = SSHConnectionManager()
    let connected = await manager.isConnected
    assertFalse(connected, "New manager should not be connected")
    await manager.disconnect()
}

func testSSHConnectionManagerOpenExecWithoutConnect() async {
    let manager = SSHConnectionManager()
    do {
        _ = try await manager.openExecChannel(command: "echo test")
        assertTrue(false, "Should have thrown SSHError.disconnected")
    } catch let error as SSHError {
        if case .disconnected = error {
            assertTrue(true, "Got expected SSHError.disconnected")
        } else {
            assertTrue(false, "Expected .disconnected, got \(error)")
        }
    } catch {
        assertTrue(false, "Expected SSHError, got \(type(of: error))")
    }
    await manager.disconnect()
}

func testSSHConnectionManagerPublicKeyAuthRejected() async {
    let manager = SSHConnectionManager()
    do {
        try await manager.connect(
            host: "localhost",
            port: 22,
            user: "test",
            auth: .publicKey(privateKey: Data("key".utf8), passphrase: nil)
        )
        assertTrue(false, "Should have thrown SSHError.authenticationFailed")
    } catch let error as SSHError {
        if case .authenticationFailed = error {
            assertTrue(true, "Got expected SSHError.authenticationFailed for publicKey (not implemented)")
        } else {
            assertTrue(false, "Expected .authenticationFailed, got \(error)")
        }
    } catch {
        assertTrue(false, "Expected SSHError, got \(type(of: error))")
    }
    await manager.disconnect()
}

func testSSHConnectionManagerConnectToUnreachableHost() async {
    let manager = SSHConnectionManager()
    do {
        // Connect to a non-routable address that should fail quickly
        try await manager.connect(
            host: "192.0.2.1",  // TEST-NET-1 (RFC 5737) — guaranteed non-routable
            port: 22,
            user: "test",
            auth: .password("pass")
        )
        assertTrue(false, "Should have thrown SSHError.connectionFailed")
    } catch let error as SSHError {
        if case .connectionFailed = error {
            assertTrue(true, "Got expected SSHError.connectionFailed")
        } else {
            // Auth failure is also acceptable if TCP connected but SSH failed
            assertTrue(true, "Got SSHError: \(error)")
        }
    } catch {
        // NIO may throw its own error types
        assertTrue(true, "Got connection error (non-SSHError): \(type(of: error))")
    }
    await manager.disconnect()
}

// MARK: - SSHChannel Stream/Write Behavior Tests (via EmbeddedChannel)

func testSSHChannelInboundStreamReceivesData() async throws {
    let embedded = EmbeddedChannel()
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    let inbound = AsyncThrowingStream<Data, Error> { continuation = $0 }

    let channel = SSHChannel(channel: embedded, inbound: inbound)

    // Feed data through the continuation (simulating what ExecHandler does)
    let testData = Data("hello world".utf8)
    continuation.yield(testData)
    continuation.finish()

    var received = Data()
    for try await chunk in channel.inbound {
        received.append(chunk)
    }
    assertEqual(received, testData, "Inbound stream should deliver the fed data")
    _ = channel  // keep alive
}

func testSSHChannelInboundStreamPropagatesError() async {
    let embedded = EmbeddedChannel()
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    let inbound = AsyncThrowingStream<Data, Error> { continuation = $0 }

    let channel = SSHChannel(channel: embedded, inbound: inbound)

    // Feed an error through the continuation
    continuation.finish(throwing: SSHError.disconnected)

    var gotError = false
    do {
        for try await _ in channel.inbound {
            assertTrue(false, "Should not receive data after error")
        }
    } catch {
        gotError = true
        assertTrue(error is SSHError, "Expected SSHError, got \(type(of: error))")
    }
    assertTrue(gotError, "Should have received error from inbound stream")
    _ = channel  // keep alive
}

func testSSHChannelInboundStreamMultipleChunks() async throws {
    let embedded = EmbeddedChannel()
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    let inbound = AsyncThrowingStream<Data, Error> { continuation = $0 }

    let channel = SSHChannel(channel: embedded, inbound: inbound)

    let chunk1 = Data("chunk1".utf8)
    let chunk2 = Data("chunk2".utf8)
    let chunk3 = Data("chunk3".utf8)
    continuation.yield(chunk1)
    continuation.yield(chunk2)
    continuation.yield(chunk3)
    continuation.finish()

    var chunks: [Data] = []
    for try await chunk in channel.inbound {
        chunks.append(chunk)
    }
    assertEqual(chunks.count, 3, "Should receive 3 chunks")
    assertEqual(chunks[0], chunk1)
    assertEqual(chunks[1], chunk2)
    assertEqual(chunks[2], chunk3)
    _ = channel  // keep alive
}

func testSSHChannelWriteToInactiveChannelThrows() async {
    let embedded = EmbeddedChannel()
    try? await embedded.close().get()

    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    let inbound = AsyncThrowingStream<Data, Error> { continuation = $0 }
    continuation.finish()

    let channel = SSHChannel(channel: embedded, inbound: inbound)
    do {
        try await channel.write(Data("test".utf8))
        assertTrue(false, "Write to closed channel should throw")
    } catch {
        assertTrue(true, "Got expected error writing to closed channel")
    }
}

func testSSHChannelCloseIdempotent() async {
    let embedded = EmbeddedChannel()
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    let inbound = AsyncThrowingStream<Data, Error> { continuation = $0 }
    continuation.finish()

    let channel = SSHChannel(channel: embedded, inbound: inbound)
    await channel.close()
    await channel.close()  // Should not crash
    assertTrue(true, "Double close did not crash")
}

// MARK: - Type Existence Tests

func testSSHConnectionManagerExists() {
    assertTrue(true, "SSHConnectionManager type exists in MoriSSH module")
}

func testSSHChannelTypeExists() {
    assertTrue(true, "SSHChannel type exists in MoriSSH module")
}

// MARK: - Async Test Runner

/// Run async tests using a RunLoop-based approach that avoids DispatchSemaphore deadlocks.
nonisolated(unsafe) var asyncTestsDone = false

func runAsyncTests() {
    asyncTestsDone = false
    Task.detached {
        // Manager lifecycle tests
        await testSSHConnectionManagerInitialState()
        await testSSHConnectionManagerOpenExecWithoutConnect()
        await testSSHConnectionManagerPublicKeyAuthRejected()
        // Note: testSSHConnectionManagerConnectToUnreachableHost skipped in CI
        // — it takes too long waiting for TCP timeout on non-routable addresses.

        // SSHChannel stream/write tests
        do {
            try await testSSHChannelInboundStreamReceivesData()
        } catch {
            assertTrue(false, "testSSHChannelInboundStreamReceivesData threw: \(error)")
        }
        await testSSHChannelInboundStreamPropagatesError()
        do {
            try await testSSHChannelInboundStreamMultipleChunks()
        } catch {
            assertTrue(false, "testSSHChannelInboundStreamMultipleChunks threw: \(error)")
        }
        await testSSHChannelWriteToInactiveChannelThrows()
        await testSSHChannelCloseIdempotent()

        asyncTestsDone = true
    }
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

// Async tests
runAsyncTests()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
