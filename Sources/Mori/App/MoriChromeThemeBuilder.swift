import AppKit
import MoriTerminal
import MoriUI

@MainActor
enum MoriChromeThemeBuilder {
    static func palette(from themeInfo: GhosttyThemeInfo) -> MoriChromePalette {
        let ghosttyBackground = themeInfo.background.usingColorSpace(.sRGB) ?? themeInfo.background
        let windowBase = themeInfo.isDark
            ? NSColor(srgbRed: 0.12, green: 0.125, blue: 0.14, alpha: 1)
            : NSColor(srgbRed: 0.955, green: 0.96, blue: 0.972, alpha: 1)
        let sidebarBase = themeInfo.isDark
            ? NSColor(srgbRed: 0.10, green: 0.105, blue: 0.12, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.94, blue: 0.955, alpha: 1)
        let panelBase = themeInfo.isDark
            ? NSColor(srgbRed: 0.145, green: 0.15, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.975, green: 0.978, blue: 0.986, alpha: 1)
        let cardBase = themeInfo.isDark
            ? NSColor(srgbRed: 0.165, green: 0.17, blue: 0.19, alpha: 1)
            : NSColor(srgbRed: 0.965, green: 0.97, blue: 0.98, alpha: 1)
        let separatorBase = themeInfo.isDark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)
        let labelBase = themeInfo.isDark ? NSColor.white : NSColor.black
        let accentFallback = NSColor.systemBlue.usingColorSpace(.sRGB) ?? .systemBlue
        let ghosttyAccent = preferredAccent(from: themeInfo) ?? accentFallback

        let windowBackground = ghosttyBackground.moriBlended(
            toward: windowBase,
            fraction: themeInfo.isDark ? 0.24 : 0.44
        )
        let sidebarBackground = windowBackground.moriBlended(
            toward: sidebarBase,
            fraction: themeInfo.isDark ? 0.22 : 0.38
        )
        let panelBackground = windowBackground.moriBlended(
            toward: panelBase,
            fraction: themeInfo.isDark ? 0.16 : 0.28
        )
        let headerBackground = panelBackground.moriBlended(
            toward: cardBase,
            fraction: themeInfo.isDark ? 0.12 : 0.20
        )
        let cardBackground = panelBackground.moriBlended(
            toward: cardBase,
            fraction: themeInfo.isDark ? 0.20 : 0.32
        )

        let selectionAccent = adjustedSelectionAccent(
            ghosttyAccent.moriBlended(toward: accentFallback, fraction: 0.22),
            against: sidebarBackground,
            isDark: themeInfo.isDark
        )

        let divider = sidebarBackground
            .moriBlended(toward: separatorBase, fraction: themeInfo.isDark ? 0.62 : 0.88)
            .withAlphaComponent(themeInfo.isDark ? 0.72 : 0.95)
        let hoverFill = labelBase.withAlphaComponent(themeInfo.isDark ? 0.10 : 0.12)
        let inactiveIconFill = labelBase.withAlphaComponent(themeInfo.isDark ? 0.08 : 0.10)
        let shortcutPillFill = labelBase.withAlphaComponent(themeInfo.isDark ? 0.10 : 0.12)
        let rowSelectionLeading = selectionAccent.withAlphaComponent(themeInfo.isDark ? 0.20 : 0.24)
        let rowSelectionTrailing = selectionAccent.withAlphaComponent(themeInfo.isDark ? 0.02 : 0.08)
        let strongSelectionFill = selectionAccent.moriBlended(
            toward: sidebarBackground,
            fraction: themeInfo.isDark ? 0.08 : 0.14
        )

        return MoriChromePalette(
            isDark: themeInfo.isDark,
            windowBackground: MoriChromeColor(nsColor: windowBackground),
            sidebarBackground: MoriChromeColor(nsColor: sidebarBackground),
            panelBackground: MoriChromeColor(nsColor: panelBackground),
            headerBackground: MoriChromeColor(nsColor: headerBackground),
            cardBackground: MoriChromeColor(nsColor: cardBackground),
            divider: MoriChromeColor(nsColor: divider),
            hoverFill: MoriChromeColor(nsColor: hoverFill),
            inactiveIconFill: MoriChromeColor(nsColor: inactiveIconFill),
            shortcutPillFill: MoriChromeColor(nsColor: shortcutPillFill),
            rowSelectionLeading: MoriChromeColor(nsColor: rowSelectionLeading),
            rowSelectionTrailing: MoriChromeColor(nsColor: rowSelectionTrailing),
            strongSelectionFill: MoriChromeColor(nsColor: strongSelectionFill),
            selectionAccent: MoriChromeColor(nsColor: selectionAccent)
        )
    }

    private static func preferredAccent(from themeInfo: GhosttyThemeInfo) -> NSColor? {
        let candidates = [12, 4, 14, 6]
        for index in candidates where themeInfo.palette.indices.contains(index) {
            let color = themeInfo.palette[index].usingColorSpace(.sRGB) ?? themeInfo.palette[index]
            let luminance = color.moriRelativeLuminance
            if luminance > 0.18, luminance < 0.90 {
                return color
            }
        }
        return nil
    }

    private static func adjustedSelectionAccent(_ color: NSColor, against background: NSColor, isDark: Bool) -> NSColor {
        let backgroundLuminance = background.moriRelativeLuminance
        var candidate = color.usingColorSpace(.sRGB) ?? color

        for _ in 0..<4 {
            let contrast = abs(candidate.moriRelativeLuminance - backgroundLuminance)
            if contrast >= (isDark ? 0.36 : 0.28) {
                return candidate
            }
            let target = isDark ? NSColor.white : NSColor.black
            candidate = candidate.moriBlended(toward: target, fraction: 0.16)
        }

        return candidate
    }
}

private extension NSColor {
    var moriSRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = usingColorSpace(.sRGB) ?? self
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    var moriRelativeLuminance: CGFloat {
        let components = moriSRGBComponents
        return 0.2126 * components.red + 0.7152 * components.green + 0.0722 * components.blue
    }

    func moriBlended(toward color: NSColor, fraction: CGFloat) -> NSColor {
        let source = usingColorSpace(.sRGB) ?? self
        let target = color.usingColorSpace(.sRGB) ?? color
        return source.blended(withFraction: fraction, of: target) ?? source
    }
}
