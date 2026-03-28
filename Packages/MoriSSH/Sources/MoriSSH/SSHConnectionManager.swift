import Foundation
import NIOCore
import NIOPosix
import NIOSSH

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
        guard !offered else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true

        guard availableMethods.contains(.password) else {
            nextChallengePromise.succeed(nil)
            return
        }
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

/// Accept-all host key delegate for the spike.
/// TODO: TOFU (trust on first use) for production.
private final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, Sendable {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
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
        if event is UserAuthSuccessEvent, let promise = authPromise {
            authPromise = nil
            promise.succeed(())
            // Remove ourselves from the pipeline — no longer needed.
            try? context.pipeline.syncOperations.removeHandler(context: context)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let promise = authPromise {
            authPromise = nil
            promise.fail(SSHError.authenticationFailed)
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let promise = authPromise {
            authPromise = nil
            promise.fail(SSHError.authenticationFailed)
        }
        context.fireErrorCaught(error)
    }
}

// MARK: - Exec Channel Handler

/// NIO channel handler that sends an exec request on channel active,
/// waits for `ChannelSuccessEvent` (exec accepted) before signaling readiness,
/// reads SSHChannelData and feeds decoded bytes into the stream continuation.
private final class ExecHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let command: String
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let execAccepted: EventLoopPromise<Void>

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
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: command,
            wantReply: true
        )
        context.triggerUserOutboundEvent(execRequest).assumeIsolated().whenFailure { error in
            self.execAccepted.fail(SSHError.channelError("exec request failed: \(error)"))
            self.continuation.finish(throwing: SSHError.channelError("exec request failed: \(error)"))
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            execAccepted.succeed(())
        case is ChannelFailureEvent:
            execAccepted.fail(SSHError.channelError("exec request rejected by server"))
            continuation.finish(throwing: SSHError.channelError("exec request rejected by server"))
            context.close(promise: nil)
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
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
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
            tcpChannel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        // Wait for SSH authentication to complete before returning
        do {
            try await authPromise.futureResult.get()
        } catch {
            // Auth failed — close the TCP channel and propagate the error
            try? await tcpChannel.close().get()
            if error is SSHError {
                throw error
            }
            throw SSHError.authenticationFailed
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

    /// Whether the connection is currently active.
    public var isConnected: Bool {
        channel?.isActive ?? false
    }
}
