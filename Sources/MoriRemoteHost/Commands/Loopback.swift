import ArgumentParser
import Foundation

/// Run the relay-free loopback test harness.
struct Loopback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run relay-free loopback harness for end-to-end testing."
    )

    @Option(name: .long, help: "Port for the loopback relay (default: 9876)")
    var port: UInt16 = 9876

    func run() async throws {
        try await LoopbackHarness.run(port: port)
    }
}
