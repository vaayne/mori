import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import os.log

private let sshLog = Logger(subsystem: "dev.mori.remote", category: "SSH")

// MARK: - Auth Delegate

/// Password-based auth delegate for the spike.
/// Offers credentials once; returns nil on subsequent calls (server-rejected auth fails cleanly).
/// Marked @unchecked Sendable: mutable state is only accessed from the NIO event loop.
private final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String
    private var offered = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        sshLog.info("nextAuthenticationType called, offered=\(self.offered), available=\(availableMethods.rawValue), hasPassword=\(availableMethods.contains(.password))")
        guard !offered else {
            sshLog.info("Already offered credentials, returning nil")
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true

        guard availableMethods.contains(.password) else {
            sshLog.warning("Server does not support password auth")
            nextChallengePromise.succeed(nil)
            return
        }
        sshLog.info("Offering password auth for user: \(self.username)")
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
        )
    }
}

// MARK: - Host Key Delegate

/// SECURITY: Accept-all host key delegate — vulnerable to MITM attacks.
/// Acceptable for spike/development only. Production must implement TOFU
/// (trust-on-first-use) with persisted known_hosts or certificate pinning.
private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, Sendable {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        sshLog.warning("Accepting host key without validation (spike mode)")
        validationCompletePromise.succeed(())
    }
}

// MARK: - Auth Completion Handler

/// Listens for `UserAuthSuccessEvent` on the parent SSH channel and resolves a promise.
/// If the channel closes before auth succeeds, the promise is failed.
private final class AuthCompletionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any

    private var authPromise: EventLoopPromise<Void>?

    init(authPromise: EventLoopPromise<Void>) {
        self.authPromise = authPromise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        sshLog.info("AuthCompletionHandler event: \(type(of: event))")
        if event is UserAuthSuccessEvent, let promise = authPromise {
            authPromise = nil
            promise.succeed(())
            // Remove ourselves from the pipeline — no longer needed.
            try? context.pipeline.syncOperations.removeHandler(context: context)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        sshLog.warning("AuthCompletionHandler: channel inactive, auth pending=\(self.authPromise != nil)")
        if let promise = authPromise {
            authPromise = nil
            promise.fail(SSHError.authenticationFailed)
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        sshLog.error("AuthCompletionHandler error: \(error)")
        if let promise = authPromise {
            authPromise = nil
            promise.fail(SSHError.authenticationFailed)
        }
        context.fireErrorCaught(error)
    }
}

// MARK: - Shell Handler

/// Channel handler that allocates a PTY and requests the user's login shell.
private final class ShellHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let cols: Int
    private let rows: Int
    private let term: String
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let shellAccepted: EventLoopPromise<Void>
    private var shellResolved = false
    private var ptyAccepted = false
    private var shellSent = false

    init(
        cols: Int,
        rows: Int,
        term: String,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        shellAccepted: EventLoopPromise<Void>
    ) {
        self.cols = cols
        self.rows = rows
        self.term = term
        self.continuation = continuation
        self.shellAccepted = shellAccepted
    }

    private func failShell(_ error: Error) {
        guard !shellResolved else { return }
        shellResolved = true
        shellAccepted.fail(error)
    }

    private func succeedShell() {
        guard !shellResolved else { return }
        shellResolved = true
        shellAccepted.succeed(())
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .assumeIsolated()
            .whenFailure { error in
                context.fireErrorCaught(error)
            }
    }

    func channelActive(context: ChannelHandlerContext) {
        sshLog.info("ShellHandler: channelActive, requesting PTY \(self.cols)x\(self.rows)")
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:])
        )
        context.triggerUserOutboundEvent(ptyRequest).assumeIsolated().whenFailure { [self] error in
            self.failShell(SSHError.channelError("pty request failed: \(error)"))
            self.continuation.finish(throwing: SSHError.channelError("pty request failed: \(error)"))
            context.close(promise: nil)
        }
    }

    private func sendShellRequest(context: ChannelHandlerContext) {
        shellSent = true
        sshLog.info("ShellHandler: PTY accepted, sending shell request")
        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        context.triggerUserOutboundEvent(shellRequest).assumeIsolated().whenFailure { [self] error in
            self.failShell(SSHError.channelError("shell request failed: \(error)"))
            self.continuation.finish(throwing: SSHError.channelError("shell request failed: \(error)"))
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            if !ptyAccepted {
                sshLog.info("ShellHandler: PTY accepted")
                ptyAccepted = true
                sendShellRequest(context: context)
            } else if shellSent {
                sshLog.info("ShellHandler: shell accepted")
                succeedShell()
            }
        case is ChannelFailureEvent:
            if !ptyAccepted {
                failShell(SSHError.channelError("pty request rejected by server"))
                continuation.finish(throwing: SSHError.channelError("pty request rejected by server"))
                context.close(promise: nil)
            } else {
                failShell(SSHError.channelError("shell request rejected by server"))
                continuation.finish(throwing: SSHError.channelError("shell request rejected by server"))
                context.close(promise: nil)
            }
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else { return }
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        sshLog.debug("ShellHandler: read \(bytes.count) bytes")
        continuation.yield(Data(bytes))
    }

    func channelInactive(context: ChannelHandlerContext) {
        sshLog.info("ShellHandler: channel inactive")
        failShell(SSHError.disconnected)
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failShell(error)
        continuation.finish(throwing: error)
        context.close(promise: nil)
    }
}

// MARK: - Exec Handler

private final class ExecHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let command: String
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let execAccepted: EventLoopPromise<Void>
    private var ptyAccepted = false
    private var execSent = false
    private var execResolved = false

    private func succeedExec() {
        guard !execResolved else { return }
        execResolved = true
        execAccepted.succeed(())
    }

    private func failExec(_ error: Error) {
        guard !execResolved else { return }
        execResolved = true
        execAccepted.fail(error)
    }

    init(
        command: String,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        execAccepted: EventLoopPromise<Void>
    ) {
        self.command = command
        self.continuation = continuation
        self.execAccepted = execAccepted
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .assumeIsolated()
            .whenFailure { error in
                context.fireErrorCaught(error)
            }
    }

    func channelActive(context: ChannelHandlerContext) {
        // Request a PTY first — tmux control mode requires a TTY
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([.ECHO: 0])
        )
        context.triggerUserOutboundEvent(ptyRequest).assumeIsolated().whenFailure { [self] error in
            self.failExec(SSHError.channelError("pty request failed: \(error)"))
            self.continuation.finish(throwing: SSHError.channelError("pty request failed: \(error)"))
            context.close(promise: nil)
        }
    }

    private func sendExecRequest(context: ChannelHandlerContext) {
        execSent = true
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: command,
            wantReply: true
        )
        context.triggerUserOutboundEvent(execRequest).assumeIsolated().whenFailure { [self] error in
            self.failExec(SSHError.channelError("exec request failed: \(error)"))
            self.continuation.finish(throwing: SSHError.channelError("exec request failed: \(error)"))
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            if !ptyAccepted {
                // First success = PTY accepted → send exec
                ptyAccepted = true
                sendExecRequest(context: context)
            } else if execSent {
                // Second success = exec accepted
                succeedExec()
            }
        case is ChannelFailureEvent:
            if !ptyAccepted {
                failExec(SSHError.channelError("pty request rejected by server"))
                continuation.finish(throwing: SSHError.channelError("pty request rejected by server"))
                context.close(promise: nil)
            } else {
                failExec(SSHError.channelError("exec request rejected by server"))
                continuation.finish(throwing: SSHError.channelError("exec request rejected by server"))
                context.close(promise: nil)
            }
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else { return }
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        continuation.yield(Data(bytes))
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Fail execAccepted if still pending (channel closed before exec was accepted)
        failExec(SSHError.disconnected)
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Fail execAccepted if still pending
        failExec(error)
        continuation.finish(throwing: error)
        context.close(promise: nil)
    }
}

// MARK: - Connection Manager

/// Actor managing a single SSH connection to a remote host.
/// Provides the ability to open exec channels for running remote commands.
public actor SSHConnectionManager {
    private var channel: Channel?
    private let group: MultiThreadedEventLoopGroup

    public init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Connect to a remote SSH host and wait for authentication to succeed.
    ///
    /// This method returns only after both the TCP connection and SSH authentication
    /// are complete. If authentication fails, throws `SSHError.authenticationFailed`.
    ///
    /// - Parameters:
    ///   - host: The remote hostname or IP address.
    ///   - port: The SSH port (default 22).
    ///   - user: The username for authentication.
    ///   - auth: The authentication method.
    public func connect(
        host: String,
        port: Int = 22,
        user: String,
        auth: SSHAuthMethod
    ) async throws {
        let authDelegate: PasswordAuthDelegate
        switch auth {
        case .password(let password):
            authDelegate = PasswordAuthDelegate(username: user, password: password)
        case .publicKey:
            // Stretch goal — not implemented for the spike
            throw SSHError.authenticationFailed
        }

        // We create the auth promise on the event loop so the handler can resolve it
        let eventLoop = group.next()
        let authPromise = eventLoop.makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sshHandler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: AcceptAllHostKeysDelegate()
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                    try channel.pipeline.syncOperations.addHandler(
                        AuthCompletionHandler(authPromise: authPromise)
                    )
                }
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        let tcpChannel: Channel
        do {
            sshLog.info("TCP connect to \(host):\(port)…")
            tcpChannel = try await bootstrap.connect(host: host, port: port).get()
            sshLog.info("TCP connected")
        } catch {
            sshLog.error("TCP connect failed: \(error)")
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        // Wait for SSH authentication to complete before returning
        do {
            sshLog.info("Waiting for SSH auth…")
            try await authPromise.futureResult.get()
            sshLog.info("SSH auth succeeded")
        } catch {
            sshLog.error("SSH auth failed: \(error)")
            // Auth failed — close the TCP channel and propagate the error
            try? await tcpChannel.close().get()
            throw (error as? SSHError) ?? SSHError.connectionFailed("authentication failed: \(error.localizedDescription)")
        }

        self.channel = tcpChannel
    }

    /// Open an exec channel on the SSH connection and run the given command.
    ///
    /// This method returns only after the remote side has accepted the exec request
    /// (`ChannelSuccessEvent`). If the server rejects the exec, throws `SSHError.channelError`.
    ///
    /// - Parameter command: The remote command to execute (e.g., `tmux -C new-session`).
    /// - Returns: An `SSHChannel` for reading output and writing input.
    public func openExecChannel(command: String) async throws -> SSHChannel {
        guard let channel = self.channel else {
            throw SSHError.disconnected
        }

        let sshChannel: SSHChannel = try await withCheckedThrowingContinuation { continuation in
            channel.eventLoop.execute {
                let sshHandler: NIOSSHHandler
                do {
                    sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                } catch {
                    continuation.resume(throwing: SSHError.channelError("no SSH handler: \(error)"))
                    return
                }

                let channelPromise = channel.eventLoop.makePromise(of: Channel.self)
                let execAccepted = channel.eventLoop.makePromise(of: Void.self)
                var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation!
                let inbound = AsyncThrowingStream<Data, Error> { streamContinuation = $0 }

                sshHandler.createChannel(channelPromise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            SSHError.channelError("unexpected channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        let handler = ExecHandler(
                            command: command,
                            continuation: streamContinuation,
                            execAccepted: execAccepted
                        )
                        try childChannel.pipeline.syncOperations.addHandler(handler)
                    }
                }

                // Wait for BOTH the child channel creation AND exec acceptance
                channelPromise.futureResult.assumeIsolated().whenComplete { result in
                    switch result {
                    case .success(let childChannel):
                        // Channel created — now wait for exec acceptance
                        execAccepted.futureResult.assumeIsolated().whenComplete { execResult in
                            switch execResult {
                            case .success:
                                let ch = SSHChannel(channel: childChannel, inbound: inbound)
                                continuation.resume(returning: ch)
                            case .failure(let error):
                                streamContinuation.finish(throwing: error)
                                continuation.resume(throwing: error)
                            }
                        }
                    case .failure(let error):
                        streamContinuation.finish(throwing: error)
                        execAccepted.fail(error)
                        continuation.resume(throwing: SSHError.channelError(error.localizedDescription))
                    }
                }
            }
        }

        return sshChannel
    }

    /// Open an interactive shell channel with a PTY.
    ///
    /// Allocates a pseudo-terminal and starts the user's login shell.
    /// Use `SSHChannel.resize(cols:rows:)` to send window-change requests.
    ///
    /// - Parameters:
    ///   - cols: Initial terminal width in columns (default 80).
    ///   - rows: Initial terminal height in rows (default 24).
    ///   - term: TERM environment variable (default xterm-256color).
    /// - Returns: An `SSHChannel` for reading output and writing input.
    public func openShellChannel(
        cols: Int = 80,
        rows: Int = 24,
        term: String = "xterm-256color"
    ) async throws -> SSHChannel {
        guard let channel = self.channel else {
            throw SSHError.disconnected
        }

        let sshChannel: SSHChannel = try await withCheckedThrowingContinuation { continuation in
            channel.eventLoop.execute {
                let sshHandler: NIOSSHHandler
                do {
                    sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                } catch {
                    continuation.resume(throwing: SSHError.channelError("no SSH handler: \(error)"))
                    return
                }

                let channelPromise = channel.eventLoop.makePromise(of: Channel.self)
                let shellAccepted = channel.eventLoop.makePromise(of: Void.self)
                var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation!
                let inbound = AsyncThrowingStream<Data, Error> { streamContinuation = $0 }

                sshHandler.createChannel(channelPromise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            SSHError.channelError("unexpected channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        let handler = ShellHandler(
                            cols: cols,
                            rows: rows,
                            term: term,
                            continuation: streamContinuation,
                            shellAccepted: shellAccepted
                        )
                        try childChannel.pipeline.syncOperations.addHandler(handler)
                    }
                }

                channelPromise.futureResult.assumeIsolated().whenComplete { result in
                    switch result {
                    case .success(let childChannel):
                        shellAccepted.futureResult.assumeIsolated().whenComplete { shellResult in
                            switch shellResult {
                            case .success:
                                let ch = SSHChannel(channel: childChannel, inbound: inbound)
                                continuation.resume(returning: ch)
                            case .failure(let error):
                                streamContinuation.finish(throwing: error)
                                continuation.resume(throwing: error)
                            }
                        }
                    case .failure(let error):
                        streamContinuation.finish(throwing: error)
                        shellAccepted.fail(error)
                        continuation.resume(throwing: SSHError.channelError(error.localizedDescription))
                    }
                }
            }
        }

        return sshChannel
    }

    /// Disconnect from the SSH server.
    public func disconnect() async {
        if let channel = self.channel {
            self.channel = nil
            try? await channel.close().get()
        }
        try? await group.shutdownGracefully()
    }

    /// Run a one-shot command and collect its stdout as a string.
    public func runCommand(_ command: String) async throws -> String {
        let channel = try await openExecChannel(command: command)
        var output = Data()
        for try await chunk in channel.inbound {
            output.append(chunk)
        }
        await channel.close()
        return String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Whether the connection is currently active.
    public var isConnected: Bool {
        channel?.isActive ?? false
    }
}
