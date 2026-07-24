import AppKit
import MoriTerminal
import MoriUI

/// Feeds the theme pipeline into MoriUI's observable color store: on every
/// broadcast, derives the semantic palette from the theme's ANSI table and
/// applies it to `MoriTheme.shared`, so `MoriTokens.Color.*` follows the
/// terminal theme. Falls back to the system-color defaults when the theme
/// exposes no usable palette.
///
/// Broadcasts also fire on key-window/full-screen changes (to repaint
/// translucency), where the theme is unchanged — the bridge skips identical
/// palettes so those repaints never touch the store and spuriously
/// invalidate every token-reading SwiftUI view.
@MainActor
final class MoriThemeBridge: ThemedSurface {
    private var lastApplied: SemanticPalette?

    var themedWindow: NSWindow? { nil }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        guard let palette = SemanticPalette.derive(
            background: rgb(themeInfo.background),
            foreground: rgb(themeInfo.foreground),
            ansi: themeInfo.palette.map(rgb)
        ) else {
            if lastApplied != nil {
                MoriTheme.shared.reset()
                lastApplied = nil
            }
            return
        }
        guard palette != lastApplied else { return }
        MoriTheme.shared.apply(palette)
        lastApplied = palette
    }

    private func rgb(_ color: NSColor) -> RGB {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return RGB(r: Double(r), g: Double(g), b: Double(b))
    }
}
