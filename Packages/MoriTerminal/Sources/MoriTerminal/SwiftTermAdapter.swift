import AppKit
import SwiftTerm

/// Terminal adapter backed by SwiftTerm — a full VT100/xterm emulator.
/// Provides cursor rendering, colors, mouse support, and proper tmux compatibility.
@MainActor
public final class SwiftTermAdapter: TerminalHost {

    public init() {}

    public func createSurface(command: String, workingDirectory: String) -> NSView {
        let termView = LocalProcessTerminalView(frame: .zero)
        termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Start a login shell that runs the tmux command.
        // Note: SwiftTerm prepends executable as argv[0], so args should NOT include it.
        let shell = "/bin/zsh"
        let args = ["-l", "-c", command]
        let env = processEnvironment()

        termView.startProcess(
            executable: shell,
            args: args,
            environment: env,
            execName: shell,
            currentDirectory: workingDirectory
        )

        return termView
    }

    public func destroySurface(_ surface: NSView) {
        guard let termView = surface as? LocalProcessTerminalView else { return }
        let terminal = termView.getTerminal()
        terminal.sendResponse(text: "\u{04}")  // Ctrl+D / EOF
    }

    public func surfaceDidResize(_ surface: NSView, to size: NSSize) {
        // SwiftTerm handles resize automatically via NSView layout
    }

    public func focusSurface(_ surface: NSView) {
        surface.window?.makeFirstResponder(surface)
    }

    // MARK: - Helpers

    private func processEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        return env.map { "\($0.key)=\($0.value)" }
    }
}
