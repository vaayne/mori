import AppKit
import MoriCore
import SwiftTerm

/// Terminal adapter backed by SwiftTerm — a full VT100/xterm emulator.
/// Provides cursor rendering, colors, mouse support, and proper tmux compatibility.
@MainActor
public final class SwiftTermAdapter: TerminalHost {

    public var settings: TerminalSettings {
        didSet {
            if settings != oldValue {
                settings.save()
            }
        }
    }

    public init(settings: TerminalSettings = .load()) {
        self.settings = settings
    }

    public func createSurface(command: String, workingDirectory: String) -> NSView {
        let termView = LocalProcessTerminalView(frame: .zero)
        configureTerminalView(termView)

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

    /// Apply current settings to an existing terminal surface.
    /// TODO: Live update does not visually take effect while tmux is running —
    /// tmux controls its own fg/bg via escape sequences, overriding SwiftTerm's defaults.
    /// Font changes work; color/theme changes only apply to newly created surfaces.
    public func applySettings(to surface: NSView) {
        guard let termView = surface as? LocalProcessTerminalView else { return }
        configureTerminalView(termView)
    }

    // MARK: - Private

    private func configureTerminalView(_ termView: LocalProcessTerminalView) {
        // Font
        let font = resolveFont()
        termView.font = font

        // Theme colors — set fg/bg/caret/selection before installColors,
        // because installColors triggers a full redraw via colorsChanged().
        let theme = settings.theme
        termView.nativeForegroundColor = NSColor(hex: theme.foreground)
        termView.nativeBackgroundColor = NSColor(hex: theme.background)
        termView.caretColor = NSColor(hex: theme.cursor)
        termView.selectedTextBackgroundColor = NSColor(hex: theme.selection)

        // ANSI palette — installColors calls colorsChanged() which flushes
        // the color cache and triggers a full display refresh.
        let ansiColors = theme.ansi.map { swiftTermColor(hex: $0) }
        if ansiColors.count == 16 {
            termView.installColors(ansiColors)
        }

        // Force layer background update (SwiftTerm doesn't sync this automatically)
        termView.layer?.backgroundColor = NSColor(hex: theme.background).cgColor
        termView.needsDisplay = true

        // Cursor style
        let terminal = termView.getTerminal()
        switch settings.cursorStyle {
        case .block:
            terminal.setCursorStyle(.blinkBlock)
        case .underline:
            terminal.setCursorStyle(.blinkUnderline)
        case .bar:
            terminal.setCursorStyle(.blinkBar)
        }
    }

    private func resolveFont() -> NSFont {
        let size = CGFloat(settings.fontSize)

        // Try the user-specified family first
        if let font = NSFont(name: settings.fontFamily, size: size) {
            return font
        }

        // Try common monospace font name variations
        let variations = [
            settings.fontFamily + "-Regular",
            settings.fontFamily.replacingOccurrences(of: " ", with: ""),
            settings.fontFamily.replacingOccurrences(of: " ", with: "-"),
        ]
        for name in variations {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        // Fallback to system monospace
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func processEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - Color Helpers

extension NSColor {
    public convenience init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: h)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// SwiftTerm.Color cannot have convenience inits added via extension,
// so use a factory function instead.
private func swiftTermColor(hex: String) -> SwiftTerm.Color {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)

    let r = UInt16((rgb >> 16) & 0xFF)
    let g = UInt16((rgb >> 8) & 0xFF)
    let b = UInt16(rgb & 0xFF)
    // SwiftTerm Color uses 0–65535 range
    return SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
}
