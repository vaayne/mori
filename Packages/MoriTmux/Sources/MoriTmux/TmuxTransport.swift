import Foundation

/// Abstraction over a bidirectional byte channel for tmux control-mode.
///
/// Allows `TmuxControlClient` to be tested with a mock transport
/// instead of requiring a real SSH connection.
public protocol TmuxTransport: Sendable {
    /// Incoming data chunks from the remote tmux server.
    var inbound: AsyncThrowingStream<Data, Error> { get }

    /// Write data to the remote tmux server (e.g., commands).
    func write(_ data: Data) async throws

    /// Close the transport channel.
    func close() async
}
