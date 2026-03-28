import Foundation
import NIOCore
import NIOPosix
import NIOSSH

// MARK: - Auth Delegate

/// Password-based auth delegate for the spike.
private final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate, Sendable {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.password) else {
            nextChallengePromise.fail(SSHError.authenticationFailed)
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

// MARK: - Exec Channel Handler

/// NIO channel handler that sends an exec request on channel active,
/// reads SSHChannelData and feeds decoded bytes into the stream continuation.
private final class ExecHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let command: String
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(command: String, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.command = command
        self.continuation = continuation
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
            self.continuation.finish(throwing: SSHError.channelError("exec request failed: \(error)"))
            context.close(promise: nil)
        }
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

    /// Connect to a remote SSH host.
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
        let authDelegate: NIOSSHClientUserAuthenticationDelegate
        switch auth {
        case .password(let password):
            authDelegate = PasswordAuthDelegate(username: user, password: password)
        case .publicKey:
            // Stretch goal — not implemented for the spike
            throw SSHError.authenticationFailed
        }

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
                }
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        do {
            self.channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }
    }

    /// Open an exec channel on the SSH connection and run the given command.
    ///
    /// The returned `SSHChannel` provides async access to the command's
    /// stdout/stderr and allows writing to its stdin.
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

                let promise = channel.eventLoop.makePromise(of: Channel.self)
                var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation!
                let inbound = AsyncThrowingStream<Data, Error> { streamContinuation = $0 }

                sshHandler.createChannel(promise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            SSHError.channelError("unexpected channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        let handler = ExecHandler(command: command, continuation: streamContinuation)
                        try childChannel.pipeline.syncOperations.addHandler(handler)
                    }
                }

                promise.futureResult.assumeIsolated().whenComplete { result in
                    switch result {
                    case .success(let childChannel):
                        let ch = SSHChannel(channel: childChannel, inbound: inbound)
                        continuation.resume(returning: ch)
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
