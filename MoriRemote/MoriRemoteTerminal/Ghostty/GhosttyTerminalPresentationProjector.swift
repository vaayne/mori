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
    let hasFocusedSurface: Bool
    let selectedActiveLeafID: UUID?
    let selectedWindowIndex: Int?
    let windowCount: Int
    let selectedPaneIndex: Int?
    let paneCount: Int
    let isWaitingForPanes: Bool
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

/// Remux presents exactly one tmux pane per app viewport on every supported
/// device class. Topology identities remain stable for picker actions; this
/// projection identifies the one native surface instance currently hosted.
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

enum GhosttyTmuxTopologyActionInteractionEffect: Equatable, Sendable {
    case none
    case refocusOnly
    case refocusAndDismissOnQueued

    var requestsInputRefocus: Bool {
        switch self {
        case .none:
            false
        case .refocusOnly, .refocusAndDismissOnQueued:
            true
        }
    }

    var dismissesSelectionSheetOnQueued: Bool {
        self == .refocusAndDismissOnQueued
    }
}

struct GhosttyWindowSheetPresentationProjection: Equatable, Sendable {
    let previewLeafIDs: [UUID]
}

struct GhosttyPaneSheetPresentationProjection: Equatable, Sendable {
    let topLevelID: UUID
    let previewLeafIDs: [UUID]
}

struct GhosttyPaneSelectionSheetTopologyProjection: Equatable, Sendable {
    let topLevelID: UUID?
    let shouldDismissPaneSheet: Bool
}

struct GhosttyWindowSelectionSheetRenderProjection: Equatable, Sendable {
    struct Window: Identifiable, Equatable, Sendable {
        let id: UUID
        let displayName: String
        let displayIndex: Int
        let totalCount: Int
        let paneCount: Int
        let isSelected: Bool
        let focusedPreviewPaneID: UUID?
    }

    let windows: [Window]
    let selectedWindowID: UUID?
    let previewLeafIDs: [UUID]
}

struct GhosttyPaneSelectionSheetRenderProjection: Equatable, Sendable {
    struct Pane: Identifiable, Equatable, Sendable {
        let id: UUID
        let displayIndex: Int
        let totalCount: Int
        let isSelected: Bool
    }

    let topLevelID: UUID
    let panes: [Pane]
    let selectedPaneID: UUID?
    let previewLeafIDs: [UUID]
    let paneCount: Int
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
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyTerminalScreenPresentationProjection {
        let readiness = TerminalReadinessProjector.snapshot(
            phase: phase,
            transportWritable: transportWritable,
            topLevelCount: snapshot.topLevels.count,
            selectedActiveLeafID: presentedSurfaceID
        )

        return GhosttyTerminalScreenPresentationProjection(
            readiness: readiness,
            interaction: terminalInteractionProjection(
                phase: phase,
                presentedSurfaceID: presentedSurfaceID,
                snapshot: snapshot
            ),
            viewport: GhosttyTerminalViewportPresentationProjection(
                surfaceID: presentedSurfaceID,
                windowCount: snapshot.topLevels.count
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
        presentedSurfaceID: UUID?,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyTerminalInteractionProjection {
        let selectedTopLevel = snapshot.selectedTopLevel
        let selectedPaneIndex = selectedTopLevel.flatMap { topLevel -> Int? in
            guard let focusedLeafID = topLevel.resolvedFocusedLeafID else { return nil }
            return topLevel.leafIDs.firstIndex(of: focusedLeafID)
        }
        let hasFocusedSurface = presentedSurfaceID != nil

        return GhosttyTerminalInteractionProjection(
            isInputAvailable: TerminalReadinessProjector.isInputAvailable(
                phase: phase,
                hasFocusedSurface: hasFocusedSurface
            ),
            hasFocusedSurface: hasFocusedSurface,
            selectedActiveLeafID: presentedSurfaceID,
            selectedWindowIndex: snapshot.selectedTopLevelIndex,
            windowCount: snapshot.topLevels.count,
            selectedPaneIndex: selectedPaneIndex,
            paneCount: selectedTopLevel?.leafIDs.count ?? 0,
            isWaitingForPanes: TerminalReadinessProjector.isWaitingForPanes(
                phase: phase,
                topLevelCount: snapshot.topLevels.count
            )
        )
    }

    static func createTmuxWindowInteractionEffect() -> GhosttyTmuxTopologyActionInteractionEffect {
        .refocusAndDismissOnQueued
    }

    static func splitFocusedTmuxPaneInteractionEffect() -> GhosttyTmuxTopologyActionInteractionEffect {
        .refocusAndDismissOnQueued
    }

    static func closeTmuxWindowInteractionEffect(
        _ id: UUID,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyTmuxTopologyActionInteractionEffect {
        guard snapshot.topLevels.contains(where: { $0.id == id }) else {
            return .none
        }

        return snapshot.topLevels.count <= 1 ? .refocusAndDismissOnQueued : .none
    }

    static func closeTmuxPaneInteractionEffect(
        _ id: UUID,
        inTopLevel topLevelID: UUID,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyTmuxTopologyActionInteractionEffect {
        guard
            let topLevel = snapshot.topLevels.first(where: { $0.id == topLevelID }),
            topLevel.leafIDs.contains(id)
        else {
            return .none
        }

        return topLevel.leafIDs.count == 1 ? .refocusOnly : .none
    }

    static func windowSheetPresentationProjection(
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyWindowSheetPresentationProjection? {
        guard !snapshot.topLevels.isEmpty else { return nil }

        return GhosttyWindowSheetPresentationProjection(
            previewLeafIDs: snapshot.topLevels.compactMap(\.resolvedFocusedLeafID)
        )
    }

    static func selectedPaneSheetPresentationProjection(
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyPaneSheetPresentationProjection? {
        guard let topLevel = snapshot.selectedTopLevel else { return nil }

        return GhosttyPaneSheetPresentationProjection(
            topLevelID: topLevel.id,
            previewLeafIDs: topLevel.leafIDs
        )
    }

    static func paneCount(
        topLevelID: UUID,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> Int {
        snapshot.topLevels.first(where: { $0.id == topLevelID })?.leafIDs.count ?? 0
    }

    static func paneSelectionSheetTopologyProjection(
        topLevelID: UUID?,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyPaneSelectionSheetTopologyProjection {
        guard let topLevelID else {
            return GhosttyPaneSelectionSheetTopologyProjection(
                topLevelID: nil,
                shouldDismissPaneSheet: false
            )
        }

        let topLevelExists = snapshot.topLevels.contains { $0.id == topLevelID }
        return GhosttyPaneSelectionSheetTopologyProjection(
            topLevelID: topLevelID,
            shouldDismissPaneSheet: !topLevelExists
        )
    }

    static func windowSelectionSheetRenderProjection(
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyWindowSelectionSheetRenderProjection {
        let topLevels = snapshot.topLevels
        let selectedWindowID = snapshot.selectedTopLevel?.id
        let totalCount = topLevels.count
        let windows = topLevels.enumerated().map { index, topLevel in
            GhosttyWindowSelectionSheetRenderProjection.Window(
                id: topLevel.id,
                displayName: displaySafeWindowName(topLevel.name),
                displayIndex: index + 1,
                totalCount: totalCount,
                paneCount: topLevel.leafIDs.count,
                isSelected: topLevel.id == selectedWindowID,
                focusedPreviewPaneID: topLevel.resolvedFocusedLeafID
            )
        }

        return GhosttyWindowSelectionSheetRenderProjection(
            windows: windows,
            selectedWindowID: selectedWindowID,
            previewLeafIDs: windows.compactMap(\.focusedPreviewPaneID)
        )
    }

    private static func displaySafeWindowName(_ name: String) -> String {
        name.unicodeScalars.reduce(into: "") { result, scalar in
            guard scalar.properties.generalCategory != .control else { return }
            result.unicodeScalars.append(scalar)
        }
    }

    static func paneSelectionSheetRenderProjection(
        topLevelID: UUID,
        snapshot: GhosttyRuntimeSurfaceTopologySnapshot
    ) -> GhosttyPaneSelectionSheetRenderProjection {
        guard let topLevel = snapshot.topLevels.first(where: { $0.id == topLevelID }) else {
            return GhosttyPaneSelectionSheetRenderProjection(
                topLevelID: topLevelID,
                panes: [],
                selectedPaneID: nil,
                previewLeafIDs: [],
                paneCount: 0
            )
        }

        let selectedPaneID = topLevel.resolvedFocusedLeafID
        let totalCount = topLevel.leafIDs.count
        let panes = topLevel.leafIDs.enumerated().map { index, paneID in
            GhosttyPaneSelectionSheetRenderProjection.Pane(
                id: paneID,
                displayIndex: index + 1,
                totalCount: totalCount,
                isSelected: paneID == selectedPaneID
            )
        }

        return GhosttyPaneSelectionSheetRenderProjection(
            topLevelID: topLevelID,
            panes: panes,
            selectedPaneID: selectedPaneID,
            previewLeafIDs: topLevel.leafIDs,
            paneCount: totalCount
        )
    }
}
