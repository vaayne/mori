import Foundation

/// The terminal core speaks only this sans-I/O wire boundary. Phase 2 will
/// adapt Mori's SSH transport; keeping it protocol-only prevents the transplant
/// from depending on SSH, account, SFTP, or forwarding types.
protocol TmuxControlTransport: Sendable {
    var receivedBytes: AsyncThrowingStream<Data, Error> { get }
    func prepare() async
    func start(initialViewport: TmuxControlViewport?) async throws
    func send(_ data: Data) async throws
    func close(disposition: TmuxControlTransportCloseDisposition) async
}

protocol TmuxControlTransportLivenessChecking: Sendable {
    func isControlChannelActive() async -> Bool
}

enum TmuxControlTransportCloseDisposition: Equatable, Sendable {
    case reusable
    case invalidated
}

extension TmuxControlTransport {
    func prepare() async {}
}
