import Foundation
import NIOCore
import NIOSSH

/// Wrapper around a NIO SSH child channel providing async read/write access.
/// Exposes inbound data as an `AsyncThrowingStream` and write access via `write(_:)`.
public final class SSHExecChannel: Sendable {
    private let channel: NIOLoopBound<Channel>
    private let eventLoop: any EventLoop

    /// Stream of inbound data from the SSH channel.
    public let inbound: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(channel: Channel) {
        self.eventLoop = channel.eventLoop
        self.channel = NIOLoopBound(channel, eventLoop: channel.eventLoop)

        var cont: AsyncThrowingStream<Data, Error>.Continuation!
        self.inbound = AsyncThrowingStream { cont = $0 }
        self.continuation = cont
    }

    /// Feed data from the channel handler into the inbound stream.
    func feedInbound(_ data: Data) {
        continuation.yield(data)
    }

    /// Signal the inbound stream has finished (channel closed or EOF).
    func feedError(_ error: Error) {
        continuation.finish(throwing: error)
    }

    /// Signal clean EOF on the inbound stream.
    func feedEOF() {
        continuation.finish()
    }

    /// Write data to the SSH channel (sends to remote process stdin).
    public func write(_ data: Data) async throws {
        try await eventLoop.submit {
            let channel = self.channel.value
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
            channel.writeAndFlush(channelData, promise: nil)
        }.get()
    }

    /// Close the SSH channel.
    public func close() async {
        do {
            try await eventLoop.submit {
                self.channel.value.close(promise: nil)
            }.get()
        } catch {
            // Channel may already be closed
        }
    }
}
