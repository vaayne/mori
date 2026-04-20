import AppKit
import Combine
import SwiftUI

public struct MoriChromeColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(color.redComponent)
        self.green = Double(color.greenComponent)
        self.blue = Double(color.blueComponent)
        self.alpha = Double(color.alphaComponent)
    }

    public var color: SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    public func withAlpha(_ alpha: Double) -> MoriChromeColor {
        MoriChromeColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public struct MoriChromePalette: Sendable, Equatable {
    public let isDark: Bool
    public let isTransparent: Bool
    public let windowBackground: MoriChromeColor
    public let sidebarBackground: MoriChromeColor
    public let panelBackground: MoriChromeColor
    public let headerBackground: MoriChromeColor
    public let cardBackground: MoriChromeColor
    public let divider: MoriChromeColor
    public let hoverFill: MoriChromeColor
    public let inactiveIconFill: MoriChromeColor
    public let shortcutPillFill: MoriChromeColor
    public let rowSelectionLeading: MoriChromeColor
    public let rowSelectionTrailing: MoriChromeColor
    public let strongSelectionFill: MoriChromeColor
    public let selectionAccent: MoriChromeColor

    public init(
        isDark: Bool,
        isTransparent: Bool = false,
        windowBackground: MoriChromeColor,
        sidebarBackground: MoriChromeColor,
        panelBackground: MoriChromeColor,
        headerBackground: MoriChromeColor,
        cardBackground: MoriChromeColor,
        divider: MoriChromeColor,
        hoverFill: MoriChromeColor,
        inactiveIconFill: MoriChromeColor,
        shortcutPillFill: MoriChromeColor,
        rowSelectionLeading: MoriChromeColor,
        rowSelectionTrailing: MoriChromeColor,
        strongSelectionFill: MoriChromeColor,
        selectionAccent: MoriChromeColor
    ) {
        self.isDark = isDark
        self.isTransparent = isTransparent
        self.windowBackground = windowBackground
        self.sidebarBackground = sidebarBackground
        self.panelBackground = panelBackground
        self.headerBackground = headerBackground
        self.cardBackground = cardBackground
        self.divider = divider
        self.hoverFill = hoverFill
        self.inactiveIconFill = inactiveIconFill
        self.shortcutPillFill = shortcutPillFill
        self.rowSelectionLeading = rowSelectionLeading
        self.rowSelectionTrailing = rowSelectionTrailing
        self.strongSelectionFill = strongSelectionFill
        self.selectionAccent = selectionAccent
    }

    public static let fallback = MoriChromePalette(
        isDark: true,
        windowBackground: MoriChromeColor(nsColor: .windowBackgroundColor),
        sidebarBackground: MoriChromeColor(nsColor: .controlBackgroundColor),
        panelBackground: MoriChromeColor(nsColor: .underPageBackgroundColor),
        headerBackground: MoriChromeColor(nsColor: .controlBackgroundColor),
        cardBackground: MoriChromeColor(nsColor: .controlBackgroundColor),
        divider: MoriChromeColor(nsColor: NSColor.separatorColor.withAlphaComponent(0.7)),
        hoverFill: MoriChromeColor(nsColor: NSColor.labelColor.withAlphaComponent(0.10)),
        inactiveIconFill: MoriChromeColor(nsColor: NSColor.labelColor.withAlphaComponent(0.08)),
        shortcutPillFill: MoriChromeColor(nsColor: NSColor.labelColor.withAlphaComponent(0.08)),
        rowSelectionLeading: MoriChromeColor(nsColor: NSColor.controlAccentColor.withAlphaComponent(0.18)),
        rowSelectionTrailing: MoriChromeColor(nsColor: NSColor.controlAccentColor.withAlphaComponent(0.03)),
        strongSelectionFill: MoriChromeColor(nsColor: NSColor.controlAccentColor),
        selectionAccent: MoriChromeColor(nsColor: NSColor.controlAccentColor)
    )
}

public final class MoriChromePaletteStore: ObservableObject {
    @Published public var palette: MoriChromePalette

    public init(palette: MoriChromePalette = .fallback) {
        self.palette = palette
    }
}
