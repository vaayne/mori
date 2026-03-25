import ArgumentParser
import Foundation

@main
struct MoriRemoteHost: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mori-remote-host",
        abstract: .localized("Mori Remote Host — bridges local tmux sessions to a cloud relay via WebSocket."),
        subcommands: [
            Serve.self,
            Sessions.self,
            QRCode.self,
            Loopback.self,
        ],
        defaultSubcommand: Serve.self
    )
}
