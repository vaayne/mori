import AppKit
import MoriCore

/// Protocol abstracting terminal surface lifecycle.
/// Implementors provide an NSView that renders a terminal and runs a shell command.
///
/// Two implementations:
/// - `NativeTerminalAdapter` (PTY-based fallback, always available)
/// - `GhosttyAdapter` (libghostty-backed, requires GhosttyKit XCFramework)
@MainActor
public protocol TerminalHost: AnyObject {

    /// Current terminal settings (font, theme, cursor).
    var settings: TerminalSettings { get set }

    /// Create a terminal surface view running the given command in the specified directory.
    /// The returned NSView is ready to be added to a view hierarchy.
    func createSurface(command: String, workingDirectory: String) -> NSView

    /// Destroy a previously created surface, releasing resources.
    func destroySurface(_ surface: NSView)

    /// Notify the terminal that its container was resized.
    func surfaceDidResize(_ surface: NSView, to size: NSSize)

    /// Make the given surface the active input target.
    func focusSurface(_ surface: NSView)

    /// Apply current settings to an existing surface (e.g., after user changes theme/font).
    func applySettings(to surface: NSView)
}
