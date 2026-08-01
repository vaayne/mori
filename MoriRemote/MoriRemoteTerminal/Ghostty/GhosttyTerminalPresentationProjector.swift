import Foundation

struct TerminalReadinessSnapshot: Equatable, Sendable {
    let phase: GhosttyTerminalRuntimePhase
    let transportWritable: Bool
    let topLevelCount: Int
    let selectedActiveLeafID: UUID?

    init(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool,
        topLevelCount: Int,
        selectedActiveLeafID: UUID?
    ) {
        precondition(topLevelCount >= 0, "topLevelCount must be non-negative")
        self.phase = phase
        self.transportWritable = transportWritable
        self.topLevelCount = topLevelCount
        self.selectedActiveLeafID = selectedActiveLeafID
    }

    var hasFocusedSurface: Bool {
        selectedActiveLeafID != nil
    }
}

enum TerminalReadinessProjector {
    static func snapshot(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool,
        topLevelCount: Int,
        selectedActiveLeafID: UUID?
    ) -> TerminalReadinessSnapshot {
        TerminalReadinessSnapshot(
            phase: phase,
            transportWritable: transportWritable,
            topLevelCount: topLevelCount,
            selectedActiveLeafID: selectedActiveLeafID
        )
    }

    static func runtimeState(_ snapshot: TerminalReadinessSnapshot) -> TerminalRuntimeState {
        runtimeState(
            phase: snapshot.phase,
            hasFocusedSurface: snapshot.hasFocusedSurface
        )
    }

    static func runtimeState(
        phase: GhosttyTerminalRuntimePhase,
        hasFocusedSurface: Bool
    ) -> TerminalRuntimeState {
        if phase == .running, hasFocusedSurface {
            return .connected
        }

        switch phase {
        case .idle, .starting, .running:
            return .connecting
        case .failed(let message, let reason):
            return .disconnected(
                reason ?? TerminalDisconnectReason(
                    kind: .unknown,
                    message: message
                )
            )
        }
    }

    static func isInputAvailable(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        isInputAvailable(
            phase: snapshot.phase,
            hasFocusedSurface: snapshot.hasFocusedSurface
        )
    }

    static func isInputAvailable(
        phase: GhosttyTerminalRuntimePhase,
        hasFocusedSurface: Bool
    ) -> Bool {
        phase == .running && hasFocusedSurface
    }

    static func isTransportAvailableForInput(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        isTransportAvailableForInput(
            phase: snapshot.phase,
            transportWritable: snapshot.transportWritable
        )
    }

    static func isTransportAvailableForInput(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool
    ) -> Bool {
        phase == .running && transportWritable
    }

    static func canSubmitInput(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        canSubmitInput(
            phase: snapshot.phase,
            transportWritable: snapshot.transportWritable,
            hasFocusedSurface: snapshot.hasFocusedSurface
        )
    }

    static func uiTestInputReady(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        canSubmitInput(snapshot)
    }

    static func canSubmitInput(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool,
        hasFocusedSurface: Bool
    ) -> Bool {
        isInputAvailable(phase: phase, hasFocusedSurface: hasFocusedSurface)
            && isTransportAvailableForInput(phase: phase, transportWritable: transportWritable)
    }

    static func isWaitingForPanes(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        isWaitingForPanes(phase: snapshot.phase, topLevelCount: snapshot.topLevelCount)
    }

    static func isWaitingForPanes(
        phase: GhosttyTerminalRuntimePhase,
        topLevelCount: Int
    ) -> Bool {
        precondition(topLevelCount >= 0, "topLevelCount must be non-negative")
        return phase == .running && topLevelCount == 0
    }

    static func isTerminalStatusReady(
        _ snapshot: TerminalReadinessSnapshot,
        commandFailureMessage: String?
    ) -> Bool {
        snapshot.phase == .running
            && snapshot.topLevelCount > 0
            && commandFailureMessage == nil
    }

    static func shouldTraceTerminalReady(_ snapshot: TerminalReadinessSnapshot) -> Bool {
        snapshot.phase == .running && snapshot.topLevelCount > 0
    }

    static func terminalReadyTraceFields(
        _ snapshot: TerminalReadinessSnapshot,
        managedSurfaceCount: Int,
        workspaceID: UUID
    ) -> [String: String] {
        precondition(managedSurfaceCount >= 0, "managedSurfaceCount must be non-negative")
        return [
            "topLevels": "\(snapshot.topLevelCount)",
            "managedSurfaces": "\(managedSurfaceCount)",
            "workspaceID": workspaceID.uuidString,
            "phase": traceValue(for: snapshot.phase),
            "transportWritable": "\(snapshot.transportWritable)",
            "selectedActiveLeafID": ghosttyDiagnosticShortID(snapshot.selectedActiveLeafID),
        ]
    }

    private static func traceValue(for phase: GhosttyTerminalRuntimePhase) -> String {
        switch phase {
        case .idle:
            "idle"
        case .starting:
            "starting"
        case .running:
            "running"
        case .failed:
            "failed"
        }
    }
}

struct GhosttyTerminalInteractionProjection: Equatable, Sendable {
    let isInputAvailable: Bool
}

enum GhosttyTerminalStatusOverlayProjection: Equatable, Sendable {
    case starting
    case commandFailure(String)
    case waitingForPanes(debugStatus: String, registryDebugSummary: String)
    case ready
    case failed(message: String, reason: TerminalDisconnectReason?)
}

struct GhosttyTerminalScreenPresentationProjection: Equatable {
    let readiness: TerminalReadinessSnapshot
    let interaction: GhosttyTerminalInteractionProjection
    let viewport: GhosttyTerminalViewportPresentationProjection
    let statusOverlay: GhosttyTerminalStatusOverlayProjection
}

/// MoriRemote presents exactly one tmux pane per app viewport. This projection
/// identifies the one native surface instance currently hosted.
struct GhosttyTerminalViewportPresentationProjection: Equatable {
    static let empty = GhosttyTerminalViewportPresentationProjection(
        surfaceID: nil,
        windowCount: 0
    )

    let surfaceID: UUID?
    let windowCount: Int

    var canNavigateWindows: Bool {
        windowCount > 1
    }
}

@MainActor
enum GhosttyTerminalPresentationProjector {
    static func terminalScreenPresentationProjection(
        phase: GhosttyTerminalRuntimePhase,
        transportWritable: Bool,
        commandFailureMessage: String?,
        debugStatus: String,
        registryDebugSummary: String,
        presentedSurfaceID: UUID?,
        topLevelCount: Int
    ) -> GhosttyTerminalScreenPresentationProjection {
        let readiness = TerminalReadinessProjector.snapshot(
            phase: phase,
            transportWritable: transportWritable,
            topLevelCount: topLevelCount,
            selectedActiveLeafID: presentedSurfaceID
        )

        return GhosttyTerminalScreenPresentationProjection(
            readiness: readiness,
            interaction: terminalInteractionProjection(
                phase: phase,
                presentedSurfaceID: presentedSurfaceID
            ),
            viewport: GhosttyTerminalViewportPresentationProjection(
                surfaceID: presentedSurfaceID,
                windowCount: topLevelCount
            ),
            statusOverlay: terminalStatusOverlayProjection(
                readiness: readiness,
                commandFailureMessage: commandFailureMessage,
                debugStatus: debugStatus,
                registryDebugSummary: registryDebugSummary
            )
        )
    }

    static func terminalStatusOverlayProjection(
        readiness: TerminalReadinessSnapshot,
        commandFailureMessage: String?,
        debugStatus: String,
        registryDebugSummary: String
    ) -> GhosttyTerminalStatusOverlayProjection {
        switch readiness.phase {
        case .idle, .starting:
            return .starting
        case .failed(let message, let reason):
            return .failed(message: message, reason: reason)
        case .running:
            if let commandFailureMessage {
                return .commandFailure(commandFailureMessage)
            }
            let waitingProjection = GhosttyTerminalStatusOverlayProjection.waitingForPanes(
                debugStatus: debugStatus,
                registryDebugSummary: registryDebugSummary
            )
            if TerminalReadinessProjector.isWaitingForPanes(readiness) {
                return waitingProjection
            }
            if TerminalReadinessProjector.isTerminalStatusReady(
                readiness,
                commandFailureMessage: nil
            ) {
                return .ready
            }
            return waitingProjection
        }
    }

    static func terminalInteractionProjection(
        phase: GhosttyTerminalRuntimePhase,
        presentedSurfaceID: UUID?
    ) -> GhosttyTerminalInteractionProjection {
        GhosttyTerminalInteractionProjection(
            isInputAvailable: TerminalReadinessProjector.isInputAvailable(
                phase: phase,
                hasFocusedSurface: presentedSurfaceID != nil
            )
        )
    }
}
