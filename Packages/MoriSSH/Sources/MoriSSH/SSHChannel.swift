import Foundation
import NIOCore
import NIOSSH

/// Bidirectional wrapper around an NIO SSH child channel.
/// Provides an async stream for inbound data and async write for outbound data.
public final class SSHChannel: @unchecked Sendable {
    /// Stream of data received from the remote end.
    public let inbound: AsyncThrowingStream<Data, Error>

    private let channel: any Channel

    init(channel: any Channel, inbound: AsyncThrowingStream<Data, Error>) {
        self.channel = channel
        self.inbound = inbound
    }

    /// Write data to the SSH channel.
    public func write(_ data: Data) async throws {
        guard channel.isActive else { throw SSHError.disconnected }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        try await channel.writeAndFlush(channelData).get()
    }

    /// Close the SSH channel.
    public func close() async {
        try? await channel.close().get()
    }
}

// MARK: - Channel Handler

/// Inbound handler that reads SSHChannelData and feeds decoded bytes to an AsyncThrowingStream.
final class SSHChannelDataHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.continuation = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else { return }
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        continuation.yield(Data(bytes))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        continuation.finish(throwing: error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        continuation.finish()
    }
}
