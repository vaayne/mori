import Foundation

// herdr adds fields between releases; every model here decodes only what Mori reads and
// ignores the rest, which `Decodable` does by default. Optional properties mark fields
// that are genuinely absent in some responses, not fields we are unsure about.

/// What a pane's agent is doing, as herdr sees it.
///
/// herdr owns this vocabulary. Mori's hooks report into it and herdr also derives it on its
/// own from process inspection — `done` is one it only ever derives, which is why reporting
/// uses the narrower `HerdrReportedAgentState`.
public enum HerdrAgentStatus: String, Sendable, Hashable, Codable {
    case unknown
    case idle
    case working
    case blocked
    case done

    /// Unrecognised states from a newer herdr degrade to `unknown` rather than failing the decode.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HerdrAgentStatus(rawValue: raw) ?? .unknown
    }
}

/// The states a client is allowed to report. Narrower than `HerdrAgentStatus`: the server
/// rejects anything else, so the illegal case is left unrepresentable rather than checked.
public enum HerdrReportedAgentState: String, Sendable, Hashable {
    case idle
    case working
    case blocked
    case unknown

    /// Mori's own vocabulary says "waiting" where herdr says "blocked".
    public static func fromMoriState(_ state: String) -> HerdrReportedAgentState {
        switch state {
        case "waiting": return .blocked
        default: return HerdrReportedAgentState(rawValue: state) ?? .unknown
        }
    }

    public var status: HerdrAgentStatus { HerdrAgentStatus(rawValue: rawValue) ?? .unknown }
}

public struct HerdrServerInfo: Sendable, Hashable, Codable {
    public let version: String
    public let `protocol`: Int
}

public struct HerdrWorkspace: Sendable, Hashable, Codable, Identifiable {
    public let workspaceID: String
    public let number: Int
    public let label: String?
    public let focused: Bool
    public let paneCount: Int
    public let tabCount: Int
    public let activeTabID: String?
    public let agentStatus: HerdrAgentStatus

    public var id: String { workspaceID }

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case number
        case label
        case focused
        case paneCount = "pane_count"
        case tabCount = "tab_count"
        case activeTabID = "active_tab_id"
        case agentStatus = "agent_status"
    }
}

public struct HerdrTab: Sendable, Hashable, Codable, Identifiable {
    public let tabID: String
    public let workspaceID: String
    public let number: Int
    public let label: String?
    public let focused: Bool
    public let paneCount: Int
    public let agentStatus: HerdrAgentStatus

    public var id: String { tabID }

    private enum CodingKeys: String, CodingKey {
        case tabID = "tab_id"
        case workspaceID = "workspace_id"
        case number
        case label
        case focused
        case paneCount = "pane_count"
        case agentStatus = "agent_status"
    }
}

public struct HerdrPane: Sendable, Hashable, Codable, Identifiable {
    public let paneID: String
    public let terminalID: String
    public let workspaceID: String
    public let tabID: String
    public let focused: Bool
    public let cwd: String?
    public let foregroundCwd: String?
    public let agentStatus: HerdrAgentStatus
    public let revision: Int

    public var id: String { paneID }

    private enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case terminalID = "terminal_id"
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case focused
        case cwd
        case foregroundCwd = "foreground_cwd"
        case agentStatus = "agent_status"
        case revision
    }
}

public struct HerdrAgent: Sendable, Hashable, Codable {
    public let terminalID: String
    public let agent: String
    public let agentStatus: HerdrAgentStatus
    public let workspaceID: String
    public let tabID: String
    public let paneID: String
    public let focused: Bool
    public let cwd: String?
    public let foregroundCwd: String?

    private enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case agent
        case agentStatus = "agent_status"
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case paneID = "pane_id"
        case focused
        case cwd
        case foregroundCwd = "foreground_cwd"
    }
}

/// The whole server tree in one response — the bootstrap that `HerdrEventStream` then keeps current.
public struct HerdrSnapshot: Sendable, Hashable, Codable {
    public let version: String
    public let `protocol`: Int
    public let focusedWorkspaceID: String?
    public let focusedTabID: String?
    public let focusedPaneID: String?
    public let workspaces: [HerdrWorkspace]
    public let tabs: [HerdrTab]
    public let panes: [HerdrPane]
    public let agents: [HerdrAgent]

    private enum CodingKeys: String, CodingKey {
        case version
        case `protocol`
        case focusedWorkspaceID = "focused_workspace_id"
        case focusedTabID = "focused_tab_id"
        case focusedPaneID = "focused_pane_id"
        case workspaces
        case tabs
        case panes
        case agents
    }
}

// MARK: - Response envelopes

struct HerdrSnapshotResponse: Decodable {
    let snapshot: HerdrSnapshot
}

struct HerdrWorkspaceListResponse: Decodable {
    let workspaces: [HerdrWorkspace]
}

struct HerdrAgentListResponse: Decodable {
    let agents: [HerdrAgent]
}

/// `workspace.create` answers with the whole subtree it just made.
public struct HerdrWorkspaceCreation: Sendable, Hashable, Codable {
    public let workspace: HerdrWorkspace
    public let tab: HerdrTab
    public let rootPane: HerdrPane

    private enum CodingKeys: String, CodingKey {
        case workspace
        case tab
        case rootPane = "root_pane"
    }
}
