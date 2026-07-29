import Foundation

/// Mori's typed view of one herdr server.
///
/// A backend is bound to a socket path, which is what "one server per endpoint" means in
/// practice: the local server and each remote server are separate `HerdrBackend` values
/// over separate sockets, with no shared state to keep in sync.
public struct HerdrBackend: Sendable {
    /// The oldest wire protocol this client was written against. herdr bumps it on
    /// breaking changes, so an older server is refused rather than half-understood.
    public static let minimumProtocol = 17

    public let client: HerdrClient

    public init(socketPath: String, timeout: TimeInterval = 5) {
        client = HerdrClient(socketPath: socketPath, timeout: timeout)
    }

    public var socketPath: String { client.socketPath }

    // MARK: - Handshake

    /// Confirms a server is listening and speaks a protocol this build understands.
    @discardableResult
    public func handshake() async throws -> HerdrServerInfo {
        let info = try await client.call("ping", as: HerdrServerInfo.self)
        guard info.protocol >= Self.minimumProtocol else {
            throw HerdrError.unsupportedProtocol(
                found: info.protocol,
                minimum: Self.minimumProtocol,
                version: info.version
            )
        }
        return info
    }

    /// Whether a server is reachable at all, without caring why not.
    public func isReachable() async -> Bool {
        (try? await handshake()) != nil
    }

    // MARK: - Reading state

    public func snapshot() async throws -> HerdrSnapshot {
        try await client.call("session.snapshot", as: HerdrSnapshotResponse.self).snapshot
    }

    public func workspaces() async throws -> [HerdrWorkspace] {
        try await client.call("workspace.list", as: HerdrWorkspaceListResponse.self).workspaces
    }

    public func agents() async throws -> [HerdrAgent] {
        try await client.call("agent.list", as: HerdrAgentListResponse.self).agents
    }

    // MARK: - Workspaces

    /// herdr addresses workspaces by opaque id, so Mori's identity lives in the label and
    /// has to be resolved on every lookup.
    public func workspace(labeled label: String) async throws -> HerdrWorkspace? {
        try await workspaces().first { $0.label == label }
    }

    public func createWorkspace(cwd: String, label: String?, focus: Bool) async throws -> HerdrWorkspaceCreation {
        var params: [String: JSONValue] = ["cwd": .string(cwd), "focus": .bool(focus)]
        if let label { params["label"] = .string(label) }
        return try await client.call("workspace.create", params, as: HerdrWorkspaceCreation.self)
    }

    public func focusWorkspace(id: String) async throws {
        try await client.call("workspace.focus", ["workspace_id": .string(id)])
    }

    public func closeWorkspace(id: String) async throws {
        try await client.call("workspace.close", ["workspace_id": .string(id)])
    }

    // MARK: - Panes

    public func focusPane(id: String) async throws {
        try await client.call("pane.focus", ["pane_id": .string(id)])
    }

    public func sendText(paneID: String, text: String) async throws {
        try await client.call("pane.send_text", ["pane_id": .string(paneID), "text": .string(text)])
    }

    /// Reports agent state on Mori's behalf — the herdr equivalent of the tmux hook writing
    /// `@mori-agent-state`.
    public func reportAgent(paneID: String, source: String, agent: String, state: HerdrReportedAgentState) async throws {
        try await client.call("pane.report_agent", [
            "pane_id": .string(paneID),
            "source": .string(source),
            "agent": .string(agent),
            "state": .string(state.rawValue),
        ])
    }

    // MARK: - Events

    public func eventStream(subscriptions: [HerdrSubscription]) -> HerdrEventStream {
        HerdrEventStream(client: client, subscriptions: subscriptions)
    }
}
