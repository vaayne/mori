import Foundation

/// Lightweight model describing a pane for the `paneList` IPC response.
public struct AgentPaneInfo: Codable, Sendable, Equatable {
    public let endpoint: String
    public let tmuxPaneId: String
    public let projectName: String
    public let worktreeName: String
    public let windowName: String
    public let agentState: AgentState
    public let detectedAgent: String?

    public init(
        endpoint: String,
        tmuxPaneId: String,
        projectName: String,
        worktreeName: String,
        windowName: String,
        agentState: AgentState,
        detectedAgent: String?
    ) {
        self.endpoint = endpoint
        self.tmuxPaneId = tmuxPaneId
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.windowName = windowName
        self.agentState = agentState
        self.detectedAgent = detectedAgent
    }
}
