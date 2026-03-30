import Foundation
import NIOCore
import NIOSSH

/// Bidirectional wrapper around an NIO SSH child channel.
/// Provides an async stream for inbound data and async write for outbound data.
public final class SSHChannel: @unchecked Sendable {
    /// Stream of data received from the remote end.
    public let inbound: AsyncThrowingStream<Data, Error>

    private let channel: any Channel
    private var closed = false

    public init(channel: any Channel, inbound: AsyncThrowingStream<Data, Error>) {
        self.channel = channel
        self.inbound = inbound
    }

    deinit {
        if !closed, channel.isActive {
            let ch = channel
            ch.eventLoop.execute {
                ch.close(promise: nil)
            }
        }
    }

    /// Write data to the SSH channel.
    public func write(_ data: Data) async throws {
        guard channel.isActive else { throw SSHError.disconnected }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        try await channel.writeAndFlush(channelData).get()
    }

    /// Send a PTY window-change request to resize the remote terminal.
    public func resize(cols: Int, rows: Int) async throws {
        guard channel.isActive else { throw SSHError.disconnected }
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        try await channel.triggerUserOutboundEvent(request).get()
    }

    /// Close the SSH channel.
    public func close() async {
        guard !closed else { return }
        closed = true
        try? await channel.close().get()
    }
}
