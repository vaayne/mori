import Foundation
import MoriSSH
import MoriTmux

public struct SSHChannelTransport: TmuxTransport, Sendable {
    let channel: SSHChannel

    public init(channel: SSHChannel) {
        self.channel = channel
    }

    public var inbound: AsyncThrowingStream<Data, Error> {
        channel.inbound
    }

    public func write(_ data: Data) async throws {
        try await channel.write(data)
    }

    public func close() async {
        await channel.close()
    }
}
