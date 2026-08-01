import Foundation

enum FocusedTerminalInputSubmissionResult: Equatable, Sendable, CustomStringConvertible {
    case accepted
    case empty
    case noFocusedSurface
    case transportUnavailable
    case surfaceRejected

    var isAccepted: Bool {
        switch self {
        case .accepted, .empty:
            true
        case .noFocusedSurface, .transportUnavailable, .surfaceRejected:
            false
        }
    }

    var description: String {
        switch self {
        case .accepted:
            "accepted"
        case .empty:
            "empty"
        case .noFocusedSurface:
            "noFocusedSurface"
        case .transportUnavailable:
            "transportUnavailable"
        case .surfaceRejected:
            "surfaceRejected"
        }
    }
}

enum GhosttyMouseInputSubmissionOutcome: Equatable, Sendable {
    case sent
    case noFocusedSurface
    case missingTarget(UUID)
    case transportUnavailable
    case surfaceRejected

    var isSent: Bool {
        self == .sent
    }
}
