@preconcurrency import Citadel
@preconcurrency import Crypto
import Foundation
import NIO
import NIOPosix
@preconcurrency import NIOSSH

/// Citadel supplies key decoding/authentication; the public NIOSSH APIs provide the
/// multiplexed authenticated root and its bare exec children.
struct CitadelSSHRootConnector: SSHRootConnecting, Sendable {
    let server: SavedServer
    let auth: ResolvedSSHAuth
    let trust: SSHHostTrustResolver

    func connect() async throws -> any SSHRootConnection {
        let validator = CitadelHostKeyValidator(server: server, trust: trust)
        let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelInitializer { channel in
                do {
                    let ssh = NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: try self.authenticationMethod(),
                            serverAuthDelegate: validator
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { child, _ in
                            child.eventLoop.makeFailedFuture(CitadelTransportError.unexpectedInboundChannel)
                        }
                    )
                    let authentication = SSHAuthenticationGate(eventLoop: channel.eventLoop)
                    return channel.pipeline.addHandler(ssh).flatMap {
                        channel.pipeline.addHandler(authentication)
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connectTimeout(.seconds(30))
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)

        var root: Channel?
        do {
            let channel = try await bootstrap.connect(host: server.host, port: server.port).get()
            root = channel
            let gate = try await channel.pipeline.handler(type: SSHAuthenticationGate.self).get()
            try await gate.authenticated.get()
            let ssh = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
            return CitadelSSHRootConnection(channel: channel, handler: ssh)
        } catch {
            if let root { try? await root.close() }
            throw error
        }
    }

    private func authenticationMethod() throws -> SSHAuthenticationMethod {
        switch auth {
        case let .password(username, password, _, _):
            return .passwordBased(username: username, password: password)
        case let .privateKey(username, credential, _, _):
            let passphrase = credential.passphrase.map { Data($0.utf8) }
            switch try SSHPrivateKeyInspector.inspect(credential.privateKeyPEM).keyType {
            case .ed25519:
                return .ed25519(username: username, privateKey: try .init(sshEd25519: credential.privateKeyPEM, decryptionKey: passphrase))
            case .rsa:
                return .rsa(username: username, privateKey: try .init(sshRsa: credential.privateKeyPEM, decryptionKey: passphrase))
            case .ecdsaP256:
                return .p256(username: username, privateKey: try .init(sshEcdsaP256: credential.privateKeyPEM, decryptionKey: passphrase))
            case .ecdsaP384:
                return .p384(username: username, privateKey: try .init(sshEcdsaP384: credential.privateKeyPEM, decryptionKey: passphrase))
            case .ecdsaP521:
                return .p521(username: username, privateKey: try .init(sshEcdsaP521: credential.privateKeyPEM, decryptionKey: passphrase))
            }
        }
    }
}

enum SSHAuthenticationCompletion: Equatable, Sendable {
    case succeed
    case fail(CitadelTransportError)
}

/// One-shot gate state is separate so terminal-event ordering is testable without
/// constructing an NIO pipeline.
final class SSHAuthenticationCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim(_ completion: SSHAuthenticationCompletion) -> SSHAuthenticationCompletion? {
        lock.withLock {
            guard !completed else { return nil }
            completed = true
            return completion
        }
    }
}

private final class SSHAuthenticationGate: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let authenticated: EventLoopFuture<Void>
    private let promise: EventLoopPromise<Void>
    private let completionState = SSHAuthenticationCompletionState()

    init(eventLoop: EventLoop) {
        promise = eventLoop.makePromise(of: Void.self)
        authenticated = promise.futureResult
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            complete(.succeed)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        complete(.fail(.closed), underlyingError: error)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        complete(.fail(.closed))
        context.fireChannelInactive()
    }

    private func complete(_ completion: SSHAuthenticationCompletion, underlyingError: Error? = nil) {
        guard let completion = completionState.claim(completion) else { return }
        switch completion {
        case .succeed:
            promise.succeed(())
        case .fail:
            promise.fail(underlyingError ?? CitadelTransportError.closed)
        }
    }
}

private final class CitadelHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let server: SavedServer
    let trust: SSHHostTrustResolver

    init(server: SavedServer, trust: SSHHostTrustResolver) {
        self.server = server
        self.trust = trust
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        do {
            let fields = String(openSSHPublicKey: hostKey).split(separator: " ")
            guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else {
                throw SSHHostTrustError.staleChallenge
            }
            let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
            try trust.verify(server: server, algorithm: String(fields[0]), fingerprint: "SHA256:\(digest)")
            validationCompletePromise.succeed(())
        } catch {
            // NIOSSH will not send user authentication until this promise succeeds.
            validationCompletePromise.fail(error)
        }
    }
}

enum CitadelTransportError: Error, Equatable, Sendable {
    case unexpectedInboundChannel
    case closed
    case execRejected
}

final class CitadelSSHRootConnection: SSHRootConnection, @unchecked Sendable {
    private let channel: Channel
    private let handler: NIOSSHHandler

    init(channel: Channel, handler: NIOSSHHandler) {
        self.channel = channel
        self.handler = handler
    }

    func openSessionChannel() async throws -> any SSHChildChannel {
        let child = try await channel.eventLoop.flatSubmit { [channel, handler] in
            let promise = channel.eventLoop.makePromise(of: Channel.self)
            handler.createChannel(promise, channelType: .session) { child, type in
                guard type == .session else {
                    return child.eventLoop.makeFailedFuture(CitadelTransportError.unexpectedInboundChannel)
                }
                return child.eventLoop.makeSucceededFuture(())
            }
            return promise.futureResult
        }.get()
        return CitadelControlChannel(child)
    }

    func openFileUploadSession() async throws -> any SSHFileUploadSession {
        let sftp = try await SSHUploadTimeout.run(
            timeout: .seconds(15),
            operation: { [channel] in
                try await SFTPClient.open(overAuthenticatedSSHChannel: channel)
            },
            cleanupLateSuccess: { sftp in try? await sftp.close() }
        )
        return CitadelSFTPFileUploadSession(sftp: sftp)
    }

    func close() async {
        try? await channel.close()
    }
}

final class CitadelSFTPFileUploadSession: SSHFileUploadSession, @unchecked Sendable {
    private static let chunkSize = 4 * 1024 * 1024
    private static let maxInFlightWrites = 64
    private enum State: Equatable { case open, closing, timedOut, closed }
    private let sftp: SFTPClient
    private let closeLock = NSLock()
    private var state = State.open

    init(sftp: SFTPClient) {
        self.sftp = sftp
    }

    func ensureDirectoryExists(atPath path: String) async throws {
        do {
            _ = try await operation { try await self.sftp.getAttributes(at: path) }
        } catch where isNoSuchFile(error) {
            do {
                try await operation { try await self.sftp.createDirectory(atPath: path) }
            } catch {
                do {
                    _ = try await operation { try await self.sftp.getAttributes(at: path) }
                } catch {
                    throw error
                }
            }
        }
    }

    func uploadFile(
        from localURL: URL,
        to remotePath: String,
        progress: @escaping SSHFileUploadProgressHandler
    ) async throws {
        let localFile = try FileHandle(forReadingFrom: localURL)
        defer { try? localFile.close() }
        let remoteFile = try await operation {
            try await self.sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        }
        do {
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let data = try localFile.read(upToCount: Self.chunkSize) ?? Data()
                guard !data.isEmpty else { break }
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                let writeBuffer = buffer
                let writeOffset = offset
                try await operation {
                    try await remoteFile.writePipelined(
                        writeBuffer,
                        at: writeOffset,
                        maxInFlight: Self.maxInFlightWrites
                    )
                }
                offset += UInt64(data.count)
                await progress(Int64(min(offset, UInt64(Int64.max))))
            }
            try await operation { try await remoteFile.close() }
        } catch {
            try? await remoteFile.close()
            throw error
        }
    }

    func renameFile(from temporaryPath: String, to finalPath: String) async throws {
        try await operation { try await self.sftp.rename(at: temporaryPath, to: finalPath) }
    }

    func removeFileIfExists(atPath path: String) async throws {
        do {
            try await operation { try await self.sftp.remove(at: path) }
        } catch where isNoSuchFile(error) {
            return
        }
    }

    func close() async throws {
        let action = closeLock.withLock { () -> State in
            let previous = state
            if previous == .open { state = .closing }
            return previous
        }
        switch action {
        case .closed:
            return
        case .timedOut, .closing:
            throw SSHFileUploadError.operationTimedOut
        case .open:
            do {
                try await SSHUploadTimeout.run(
                    timeout: .seconds(15),
                    operation: { try await self.sftp.close() },
                    onTimeout: { self.invalidateAfterTimeout() }
                )
                closeLock.withLock { state = .closed }
            } catch {
                invalidateAfterTimeout()
                throw error
            }
        }
    }

    private func operation<Value: Sendable>(
        _ body: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard closeLock.withLock({ state == .open }) else {
            throw SSHFileUploadError.operationTimedOut
        }
        do {
            return try await SSHUploadTimeout.run(
                timeout: .seconds(15),
                operation: body,
                onTimeout: { self.invalidateAfterTimeout() }
            )
        } catch is CancellationError {
            invalidateAfterTimeout()
            throw CancellationError()
        }
    }

    private func invalidateAfterTimeout() {
        let shouldClose = closeLock.withLock { () -> Bool in
            guard state == .open || state == .closing else { return false }
            state = .timedOut
            return true
        }
        guard shouldClose else { return }
        let sftp = self.sftp
        Task { try? await sftp.close() }
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        guard let status = error as? SFTPMessage.Status else { return false }
        return status.errorCode == .noSuchFile
    }
}

final class CitadelControlChannel: SSHChildChannel, @unchecked Sendable {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let channel: Channel
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let completion = CitadelControlCompletion()

    init(_ channel: Channel) {
        self.channel = channel
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func execute(_ command: String) async throws {
        try await channel.pipeline.addHandler(CitadelControlReadHandler(continuation: continuation, completion: completion)).get()
        try await channel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        ).get()
    }

    func write(_ data: Data) async throws {
        guard channel.isActive else { throw CitadelTransportError.closed }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)))
    }

    func isActive() async -> Bool {
        channel.isActive && !completion.finished
    }

    func close() async throws {
        completion.finish(nil, continuation: continuation)
        try await channel.close()
    }
}

private final class CitadelControlCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var finished: Bool { lock.withLock { value } }
    func finish(_ error: Error?, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        let shouldFinish = lock.withLock { guard !value else { return false }; value = true; return true }
        guard shouldFinish else { return }
        continuation.finish(throwing: error)
    }
}

private final class CitadelControlReadHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    let completion: CitadelControlCompletion

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation, completion: CitadelControlCompletion) {
        self.continuation = continuation
        self.completion = completion
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = packet.data,
              let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        if packet.type == .channel { continuation.yield(Data(bytes)) }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is NIOSSH.ChannelFailureEvent { completion.finish(CitadelTransportError.execRejected, continuation: continuation) }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        completion.finish(nil, continuation: continuation)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        completion.finish(error, continuation: continuation)
        context.close(promise: nil)
    }
}
