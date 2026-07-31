import Foundation

struct TmuxVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int

    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.major, lhs.minor) < (rhs.major, rhs.minor) }

    static func parse(_ output: String) -> TmuxVersion? {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[0] == "tmux" else { return nil }
        let pieces = fields[1].split(separator: ".", maxSplits: 1)
        guard pieces.count == 2, let major = Int(pieces[0]) else { return nil }
        let digits = pieces[1].prefix { $0.isNumber }
        guard !digits.isEmpty, let minor = Int(digits) else { return nil }
        return .init(major: major, minor: minor)
    }
}

enum TmuxCommandError: Error, Equatable, Sendable, LocalizedError {
    case invalidExecutable
    case unsafeArgument
    case malformedVersion
    case unsupportedVersion
    case ownershipMismatch
    case groupMismatch

    var errorDescription: String? {
        switch self {
        case .invalidExecutable:
            String(localized: "The tmux executable must be an absolute path or tmux.")
        case .unsafeArgument:
            String(localized: "The tmux command contains an unsupported control character.")
        case .malformedVersion:
            String(localized: "The tmux version response is invalid.")
        case .unsupportedVersion:
            String(localized: "tmux 3.2 or later is required.")
        case .ownershipMismatch:
            String(localized: "The temporary tmux session could not be verified safely.")
        case .groupMismatch:
            String(localized: "The temporary tmux session is not grouped with the requested workspace.")
        }
    }
}

/// Builds a bare non-login POSIX shell command. Every dynamic token is single-quoted;
/// the only shell expansion is the fixed PATH setup and `command -v` resolution.
enum TmuxCommandBuilder {
    static func validateExecutable(_ path: String) throws {
        guard path == "tmux" || path.hasPrefix("/") else { throw TmuxCommandError.invalidExecutable }
        try validate(path)
    }

    static func command(executable: String, arguments: [String]) throws -> String {
        try validateExecutable(executable)
        try arguments.forEach(validate)
        return TmuxShellCommand.command(executable: executable, arguments: arguments)
    }

    static func preflight(executable: String) throws -> String { try command(executable: executable, arguments: ["-V"]) }

    static func requireSupportedVersion(_ output: String) throws {
        guard let version = TmuxVersion.parse(output) else { throw TmuxCommandError.malformedVersion }
        guard version >= .init(major: 3, minor: 2) else { throw TmuxCommandError.unsupportedVersion }
    }

    static func shadowName(source: String, runtimeID: UUID) throws -> String {
        try validate(source)
        return "\(source)--mori-remote-\(runtimeID.uuidString.lowercased())"
    }

    static func createShadow(executable: String, source: String, runtimeID: UUID) throws -> String {
        let shadow = try shadowName(source: source, runtimeID: runtimeID)
        return try command(executable: executable, arguments: ["new-session", "-d", "-t", source, "-s", shadow])
    }

    /// `-f` applies flags to the newly attached control client, before it can receive navigation.
    static func attachShadow(executable: String, shadow: String) throws -> String {
        try command(executable: executable, arguments: ["-C", "attach-session", "-t", shadow, "-f", "active-pane,ignore-size"])
    }

    struct ShadowCleanupPlan: Equatable, Sendable {
        let source: String
        let shadow: String
        let runtimeID: UUID
        let verifyCommand: String
        let killCommand: String
    }

    static func cleanupPlan(executable: String, source: String, shadow: String, runtimeID: UUID) throws -> ShadowCleanupPlan {
        let expected = try shadowName(source: source, runtimeID: runtimeID)
        guard shadow == expected else { throw TmuxCommandError.ownershipMismatch }
        // Caller must parse this exact pair before issuing kill; source is never inferred from user input.
        let verify = try command(executable: executable, arguments: ["display-message", "-p", "-t", shadow, "#{session_name}\t#{session_group}"])
        let kill = try command(executable: executable, arguments: ["kill-session", "-t", shadow])
        return .init(source: source, shadow: shadow, runtimeID: runtimeID, verifyCommand: verify, killCommand: kill)
    }

    static func verifyCleanup(_ output: String, plan: ShadowCleanupPlan) throws {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 2, fields[0] == plan.shadow else { throw TmuxCommandError.ownershipMismatch }
        // tmux reports the group leader name. A source session is its own leader; a grouped shadow reports source.
        guard fields[1] == plan.source else { throw TmuxCommandError.groupMismatch }
    }

    private static func validate(_ value: String) throws {
        guard !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else { throw TmuxCommandError.unsafeArgument }
    }
}

protocol TmuxControlTransport: Sendable {
    var receivedBytes: AsyncThrowingStream<Data, Error> { get }
    func start() async throws
    func send(_ data: Data) async throws
    func isActive() async -> Bool
    func close(disposition: TmuxControlTransportCloseDisposition) async
}

enum TmuxControlTransportCloseDisposition: Equatable, Sendable { case reusable, invalidated }

/// The continuation is made once at init. `enqueue` is synchronous and
/// thread-safe, so serial controller drains retain their exact admission order.
actor TmuxSessionLink {
    private let transport: any TmuxControlTransport
    private let receive: @Sendable (Data) -> Void
    private let disconnected: @Sendable () -> Void
    private let outbound: AsyncStream<Data>
    nonisolated private let outboundContinuation: AsyncStream<Data>.Continuation
    private var writer: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var closed = false

    init(
        transport: any TmuxControlTransport,
        receive: @escaping @Sendable (Data) -> Void,
        disconnected: @escaping @Sendable () -> Void
    ) {
        self.transport = transport
        self.receive = receive
        self.disconnected = disconnected

        var continuation: AsyncStream<Data>.Continuation!
        outbound = AsyncStream { continuation = $0 }
        outboundContinuation = continuation
    }

    nonisolated func enqueue(_ bytes: Data) {
        outboundContinuation.yield(bytes)
    }

    /// Compatibility for async transport callers; writer-queue users call `enqueue`.
    func send(_ bytes: Data) {
        enqueue(bytes)
    }

    func start(beforeReceive: @escaping @Sendable () async throws -> Void = {}) async throws {
        guard writer == nil else { return }
        writer = Task { [transport, outbound] in
            for await bytes in outbound {
                do {
                    try await transport.send(bytes)
                } catch {
                    await self.fail()
                    return
                }
            }
        }
        try await transport.start()
        do {
            try await beforeReceive()
        } catch {
            await fail()
            throw error
        }
        reader = Task { [transport] in
            do {
                for try await bytes in transport.receivedBytes {
                    self.receive(bytes)
                }
            } catch {}
            if !Task.isCancelled { await self.fail() }
        }
    }

    func isActive() async -> Bool {
        guard !closed else { return false }
        return await transport.isActive()
    }

    func stop() async {
        guard !closed else { return }
        closed = true
        outboundContinuation.finish()
        writer?.cancel()
        reader?.cancel()
        await transport.close(disposition: .reusable)
    }

    private func fail() async {
        guard !closed else { return }
        closed = true
        outboundContinuation.finish()
        await transport.close(disposition: .invalidated)
        disconnected()
    }
}
