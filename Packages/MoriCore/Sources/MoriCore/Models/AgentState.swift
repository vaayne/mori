import Foundation

public enum AgentState: String, Codable, Sendable {
    case none
    case running
    case waitingForInput
    case error
    case completed
}
