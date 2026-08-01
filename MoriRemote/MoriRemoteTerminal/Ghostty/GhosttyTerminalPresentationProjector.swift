import Foundation

/// MoriRemote hosts exactly one native pane surface in its viewport. Window
/// count is retained only for horizontal adjacent-window navigation.
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
