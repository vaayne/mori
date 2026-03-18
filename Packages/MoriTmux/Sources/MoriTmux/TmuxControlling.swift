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

    /// Send keystrokes to a pane.
    func sendKeys(sessionId: String, paneId: String, keys: String) async throws

    /// Kill (destroy) a window.
    func killWindow(sessionId: String, windowId: String) async throws
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

    func sendKeys(sessionId: String, paneId: String, keys: String) async throws {
        throw TmuxError.notYetImplemented("sendKeys")
    }

    func killWindow(sessionId: String, windowId: String) async throws {
        throw TmuxError.notYetImplemented("killWindow")
    }
}
