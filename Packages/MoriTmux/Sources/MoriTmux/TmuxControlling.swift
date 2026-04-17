import Foundation

/// Full tmux control protocol as defined in PRD section 14.4.
/// Phase 1 implements: scanAll, createSession, selectWindow, killSession, isAvailable.
/// Other methods have default implementations that throw `TmuxError.notYetImplemented`.
public protocol TmuxControlling: Sendable {

    // MARK: - Phase 1 (implemented)

    /// Scan all tmux sessions, windows, and panes. Returns the full runtime tree.
    func scanAll() async throws -> [TmuxSession]

    /// Create a new tmux session with the given name and working directory.
    func createSession(name: String, cwd: String) async throws -> TmuxSession

    /// Select (activate) a window within a session.
    func selectWindow(sessionId: String, windowId: String) async throws

    /// Kill (destroy) a tmux session.
    func killSession(id: String) async throws

    /// Check if the tmux binary is available on this system.
    func isAvailable() async -> Bool

    // MARK: - Future phases (default implementations throw)

    /// Select (activate) a session.
    func selectSession(id: String) async throws

    /// Select (activate) a pane within a window.
    func selectPane(sessionId: String, paneId: String) async throws

    /// Create a new window in a session.
    func createWindow(sessionId: String, name: String?, cwd: String?) async throws -> TmuxWindow

    /// Split a pane horizontally or vertically.
    func splitPane(sessionId: String, paneId: String, horizontal: Bool, cwd: String?) async throws -> TmuxPane

    /// Rename a window.
    func renameWindow(sessionId: String, windowId: String, newName: String) async throws

    /// Rename a pane (sets its title).
    func renamePane(paneId: String, newName: String) async throws

    /// Send keystrokes to a pane.
    func sendKeys(sessionId: String, paneId: String, keys: String) async throws

    /// Kill (destroy) a window.
    func killWindow(sessionId: String, windowId: String) async throws

    /// Kill (destroy) a pane. If it is the last pane in the window, the window closes.
    func killPane(sessionId: String, paneId: String) async throws

    /// Set a tmux server-wide option.
    func setServerOption(option: String, value: String) async throws

    /// Set a tmux session option. If sessionId is nil, sets the global default.
    func setOption(sessionId: String?, option: String, value: String) async throws

    /// Set a tmux window option. If global is true, sets `-gw`. Otherwise targets a session.
    func setWindowOption(global: Bool, target: String?, option: String, value: String) async throws

    /// Force all clients to refresh their display.
    func refreshClients() async throws

    /// Navigate to a pane by direction (up/down/left/right/next/previous).
    func navigatePane(sessionId: String, direction: PaneDirection) async throws

    /// Resize the active pane in the given direction by the specified amount of cells.
    func resizePane(sessionId: String, direction: PaneDirection, amount: Int) async throws

    /// Toggle zoom on the active pane in the session.
    func togglePaneZoom(sessionId: String) async throws

    /// Equalize pane sizes in the active window (tiled layout).
    func equalizePanes(sessionId: String) async throws

    /// Capture the visible output of a pane.
    /// - Parameters:
    ///   - paneId: The tmux pane ID (e.g. "%0").
    ///   - lineCount: Number of lines to capture from the end of the pane buffer.
    /// - Returns: The captured pane output as a string.
    func capturePaneOutput(paneId: String, lineCount: Int) async throws -> String

    /// Set a global environment variable on the tmux server.
    /// New windows/panes will inherit this variable.
    func setEnvironment(name: String, value: String) async throws

    /// Unset a global environment variable from the tmux server.
    func unsetEnvironment(name: String) async throws
}

// MARK: - Default implementations for future-phase methods

public extension TmuxControlling {

    func selectSession(id: String) async throws {
        throw TmuxError.notYetImplemented("selectSession")
    }

    func selectPane(sessionId: String, paneId: String) async throws {
        throw TmuxError.notYetImplemented("selectPane")
    }

    func createWindow(sessionId: String, name: String?, cwd: String?) async throws -> TmuxWindow {
        throw TmuxError.notYetImplemented("createWindow")
    }

    func splitPane(sessionId: String, paneId: String, horizontal: Bool, cwd: String?) async throws -> TmuxPane {
        throw TmuxError.notYetImplemented("splitPane")
    }

    func renameWindow(sessionId: String, windowId: String, newName: String) async throws {
        throw TmuxError.notYetImplemented("renameWindow")
    }

    func renamePane(paneId: String, newName: String) async throws {
        throw TmuxError.notYetImplemented("renamePane")
    }

    func sendKeys(sessionId: String, paneId: String, keys: String) async throws {
        throw TmuxError.notYetImplemented("sendKeys")
    }

    func killWindow(sessionId: String, windowId: String) async throws {
        throw TmuxError.notYetImplemented("killWindow")
    }

    func killPane(sessionId: String, paneId: String) async throws {
        throw TmuxError.notYetImplemented("killPane")
    }

    func setServerOption(option: String, value: String) async throws {
        throw TmuxError.notYetImplemented("setServerOption")
    }

    func setOption(sessionId: String?, option: String, value: String) async throws {
        throw TmuxError.notYetImplemented("setOption")
    }

    func setWindowOption(global: Bool, target: String?, option: String, value: String) async throws {
        throw TmuxError.notYetImplemented("setWindowOption")
    }

    func refreshClients() async throws {
        throw TmuxError.notYetImplemented("refreshClients")
    }

    func capturePaneOutput(paneId: String, lineCount: Int) async throws -> String {
        throw TmuxError.notYetImplemented("capturePaneOutput")
    }

    func navigatePane(sessionId: String, direction: PaneDirection) async throws {
        throw TmuxError.notYetImplemented("navigatePane")
    }

    func resizePane(sessionId: String, direction: PaneDirection, amount: Int) async throws {
        throw TmuxError.notYetImplemented("resizePane")
    }

    func togglePaneZoom(sessionId: String) async throws {
        throw TmuxError.notYetImplemented("togglePaneZoom")
    }

    func equalizePanes(sessionId: String) async throws {
        throw TmuxError.notYetImplemented("equalizePanes")
    }

    func setEnvironment(name: String, value: String) async throws {
        throw TmuxError.notYetImplemented("setEnvironment")
    }

    func unsetEnvironment(name: String) async throws {
        throw TmuxError.notYetImplemented("unsetEnvironment")
    }
}
