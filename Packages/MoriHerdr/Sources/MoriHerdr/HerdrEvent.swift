import Foundation

/// One entry in an `events.subscribe` request.
///
/// Agent-status subscriptions are scoped to a single pane — herdr rejects
/// `pane.agent_status_changed` without a `pane_id` — so a subscriber has to re-subscribe
/// as panes come and go. `HerdrEventStream` is what makes that bearable.
public struct HerdrSubscription: Sendable, Hashable {
    public let type: String
    public let paneID: String?

    public init(type: String, paneID: String? = nil) {
        self.type = type
        self.paneID = paneID
    }

    var json: JSONValue {
        var fields: [String: JSONValue] = ["type": .string(type)]
        if let paneID { fields["pane_id"] = .string(paneID) }
        return .object(fields)
    }

    // The event names herdr accepts, as of protocol 17. Names Mori does not consume yet
    // are left out on purpose: an unknown name fails the whole subscribe request.
    public static let workspaceCreated = HerdrSubscription(type: "workspace.created")
    public static let workspaceUpdated = HerdrSubscription(type: "workspace.updated")
    public static let workspaceRenamed = HerdrSubscription(type: "workspace.renamed")
    public static let workspaceClosed = HerdrSubscription(type: "workspace.closed")
    public static let workspaceFocused = HerdrSubscription(type: "workspace.focused")
    public static let tabCreated = HerdrSubscription(type: "tab.created")
    public static let tabClosed = HerdrSubscription(type: "tab.closed")
    public static let tabFocused = HerdrSubscription(type: "tab.focused")
    public static let tabRenamed = HerdrSubscription(type: "tab.renamed")
    public static let paneCreated = HerdrSubscription(type: "pane.created")
    public static let paneClosed = HerdrSubscription(type: "pane.closed")
    public static let paneUpdated = HerdrSubscription(type: "pane.updated")
    public static let paneFocused = HerdrSubscription(type: "pane.focused")
    public static let paneExited = HerdrSubscription(type: "pane.exited")
    public static let paneAgentDetected = HerdrSubscription(type: "pane.agent_detected")

    public static func paneAgentStatusChanged(paneID: String) -> HerdrSubscription {
        HerdrSubscription(type: "pane.agent_status_changed", paneID: paneID)
    }
}

/// An event pushed by the server.
///
/// The wire envelope is `{"event": "<name>", "data": {"type": "<name>", ...}}` — the name is
/// repeated, so only `data` is kept. Cases cover what Mori acts on; anything else arrives as
/// `.other` rather than being dropped, so a newer herdr does not break the stream.
public enum HerdrEvent: Sendable, Hashable {
    case workspaceCreated(HerdrWorkspace)
    case workspaceUpdated(HerdrWorkspace)
    case workspaceClosed(workspaceID: String)
    case workspaceFocused(workspaceID: String)
    case workspaceRenamed(workspaceID: String, label: String?)
    case tabCreated(HerdrTab)
    case tabClosed(tabID: String, workspaceID: String?)
    case tabFocused(tabID: String, workspaceID: String?)
    case paneCreated(HerdrPane)
    case paneUpdated(HerdrPane)
    case paneClosed(paneID: String)
    case paneFocused(paneID: String)
    case paneExited(paneID: String, exitCode: Int?)
    case paneAgentDetected(paneID: String, agent: String)
    case paneAgentStatusChanged(paneID: String, status: HerdrAgentStatus, agent: String?)
    case other(name: String, data: JSONValue)

    /// The pane this event is about, when it is about one.
    public var paneID: String? {
        switch self {
        case .paneCreated(let pane), .paneUpdated(let pane): return pane.paneID
        case .paneClosed(let id), .paneFocused(let id): return id
        case .paneExited(let id, _), .paneAgentDetected(let id, _), .paneAgentStatusChanged(let id, _, _): return id
        default: return nil
        }
    }
}

extension HerdrEvent {
    /// Parses one NDJSON line from a subscription connection.
    ///
    /// Returns `nil` for lines that are not events at all (the subscription ack, most
    /// notably), leaving the caller free to feed it every line it reads.
    public static func decode(line: Data) -> HerdrEvent? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line),
              let rawName = message["event"]?.stringValue,
              let data = message["data"]
        else { return nil }

        // herdr is inconsistent about the envelope's `event` name: most arrive snake_cased
        // (`pane_agent_detected`) but `pane.agent_status_changed` keeps the dotted method
        // spelling, and its `data` carries no `type` field either. Normalising both forms
        // to one spelling means neither the current nor a fixed upstream breaks the match.
        let name = rawName.replacingOccurrences(of: ".", with: "_")

        func model<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let payload = data[key],
                  let encoded = try? JSONEncoder().encode(payload)
            else { return nil }
            return try? JSONDecoder().decode(type, from: encoded)
        }
        let paneID = data["pane_id"]?.stringValue
        let workspaceID = data["workspace_id"]?.stringValue

        switch name {
        case "workspace_created":
            if let workspace = model("workspace", as: HerdrWorkspace.self) { return .workspaceCreated(workspace) }
        case "workspace_updated":
            if let workspace = model("workspace", as: HerdrWorkspace.self) { return .workspaceUpdated(workspace) }
        case "workspace_closed":
            if let id = workspaceID { return .workspaceClosed(workspaceID: id) }
        case "workspace_focused":
            if let id = workspaceID { return .workspaceFocused(workspaceID: id) }
        case "workspace_renamed":
            if let id = workspaceID { return .workspaceRenamed(workspaceID: id, label: data["label"]?.stringValue) }
        case "tab_created":
            if let tab = model("tab", as: HerdrTab.self) { return .tabCreated(tab) }
        case "tab_closed":
            if let id = data["tab_id"]?.stringValue { return .tabClosed(tabID: id, workspaceID: workspaceID) }
        case "tab_focused":
            if let id = data["tab_id"]?.stringValue { return .tabFocused(tabID: id, workspaceID: workspaceID) }
        case "pane_created":
            if let pane = model("pane", as: HerdrPane.self) { return .paneCreated(pane) }
        case "pane_updated":
            if let pane = model("pane", as: HerdrPane.self) { return .paneUpdated(pane) }
        case "pane_closed":
            if let id = paneID { return .paneClosed(paneID: id) }
        case "pane_focused":
            if let id = paneID { return .paneFocused(paneID: id) }
        case "pane_exited":
            if let id = paneID { return .paneExited(paneID: id, exitCode: data["exit_code"]?.intValue) }
        case "pane_agent_detected":
            if let id = paneID, let agent = data["agent"]?.stringValue {
                return .paneAgentDetected(paneID: id, agent: agent)
            }
        case "pane_agent_status_changed":
            if let id = paneID {
                let raw = data["agent_status"]?.stringValue ?? data["status"]?.stringValue ?? ""
                return .paneAgentStatusChanged(
                    paneID: id,
                    status: HerdrAgentStatus(rawValue: raw) ?? .unknown,
                    agent: data["agent"]?.stringValue
                )
            }
        default:
            break
        }
        return .other(name: rawName, data: data)
    }
}
