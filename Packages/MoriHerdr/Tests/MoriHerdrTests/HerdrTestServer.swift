import Foundation
import MoriHerdr

/// A real `herdr server` on its own session and config, torn down when the tests finish.
///
/// These tests talk to the real thing on purpose: the protocol facts they encode — one
/// request per connection, per-pane agent subscriptions, state replayed on subscribe —
/// are exactly the ones a mock would let us get wrong.
final class HerdrTestServer {
    let session: String
    let socketPath: String
    let configPath: String
    private let binary: String
    private let process = Process()

    init() throws {
        session = "mori-test-\(ProcessInfo.processInfo.processIdentifier)"
        socketPath = HerdrSocketPath.resolve(session: session)
        configPath = NSTemporaryDirectory() + "herdr-test-\(ProcessInfo.processInfo.processIdentifier)/config.toml"
        binary = try Self.locateBinary()
    }

    /// Where `herdr` lives. mise installs it outside the default PATH for non-login shells,
    /// so the mise shim directory is checked before giving up.
    private static func locateBinary() throws -> String {
        if let explicit = ProcessInfo.processInfo.environment["HERDR_BIN"], !explicit.isEmpty { return explicit }
        var candidates = ["/usr/local/bin/herdr", "/opt/homebrew/bin/herdr"]
        candidates.insert(NSHomeDirectory() + "/.local/share/mise/installs/herdr/latest/herdr", at: 0)
        for path in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(path)/herdr")
        }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.notInstalled
        }
        return found
    }

    enum Failure: Error, CustomStringConvertible {
        case notInstalled
        case didNotStart(String)

        var description: String {
            switch self {
            case .notInstalled:
                return "herdr is not installed — run `mise install` (or set HERDR_BIN)"
            case .didNotStart(let detail):
                return "herdr server did not come up: \(detail)"
            }
        }
    }

    private var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HERDR_SESSION"] = session
        env["HERDR_CONFIG_PATH"] = configPath
        return env
    }

    func start() throws {
        try FileManager.default.createDirectory(
            atPath: (configPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try "".write(toFile: configPath, atomically: true, encoding: .utf8)

        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["server"]
        process.environment = environment
        let log = Pipe()
        process.standardOutput = log
        process.standardError = log
        try process.run()

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) { return }
            guard process.isRunning else {
                let output = String(data: log.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                throw Failure.didNotStart("exited with \(process.terminationStatus): \(output)")
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw Failure.didNotStart("no socket at \(socketPath) after 15s")
    }

    func stop() {
        let stopper = Process()
        stopper.executableURL = URL(fileURLWithPath: binary)
        stopper.arguments = ["server", "stop"]
        stopper.environment = environment
        stopper.standardOutput = Pipe()
        stopper.standardError = Pipe()
        try? stopper.run()
        stopper.waitUntilExit()

        if process.isRunning {
            process.terminate()
            // Give the graceful stop a moment before the tests move on.
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
        }
        try? FileManager.default.removeItem(
            atPath: (configPath as NSString).deletingLastPathComponent
        )
        try? FileManager.default.removeItem(
            atPath: HerdrSocketPath.sessionDirectory(session: session)
        )
    }
}
