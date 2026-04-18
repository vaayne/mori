import SwiftUI
import AppKit

/// Centralized design tokens for consistent styling across MoriUI views.
public enum MoriTokens {

    // MARK: - Colors

    public enum Color {
        public static let error = SwiftUI.Color.red
        public static let success = SwiftUI.Color.green
        public static let warning = SwiftUI.Color.orange
        public static let attention = SwiftUI.Color.yellow
        public static let info = SwiftUI.Color.blue
        public static let active = SwiftUI.Color.accentColor
        public static let inactive = SwiftUI.Color.gray
        public static let muted = SwiftUI.Color.secondary
    }

    // MARK: - Spacing

    public enum Spacing {
        /// 1pt — hairline spacing (e.g., between arrow icon and count)
        public static let xxs: CGFloat = 1
        /// 2pt — tightest spacing (e.g., between swatch circles)
        public static let xs: CGFloat = 2
        /// 4pt — compact spacing (e.g., between badges, inner padding)
        public static let sm: CGFloat = 4
        /// 8pt — default element spacing (e.g., HStack items in a row)
        public static let md: CGFloat = 8
        /// 10pt — section/group spacing (e.g., vertical padding, rail items)
        public static let lg: CGFloat = 10
        /// 16pt — generous padding (e.g., header horizontal padding, content inset)
        public static let xl: CGFloat = 16
        /// 20pt — indent/large gaps (e.g., window row indent under worktree)
        public static let xxl: CGFloat = 20
        /// 40pt — large empty state offset
        public static let emptyState: CGFloat = 40
    }

    // MARK: - Corner Radius

    public enum Radius {
        /// 3pt — badges, small pills
        public static let badge: CGFloat = 3
        /// 7pt — default for rows, previews
        public static let small: CGFloat = 7
        /// 10pt — cards, panels
        public static let medium: CGFloat = 10
    }

    // MARK: - Icon Sizes

    public enum Icon {
        /// 11pt — badge icons (error, waiting, running, etc.)
        public static let badge: CGFloat = 11
        /// 8pt — status indicator dots, arrow icons
        public static let indicator: CGFloat = 8
        /// 6pt — small dots (unread, active marker, dirty)
        public static let dot: CGFloat = 6
        /// 28pt — worktree icon box size
        public static let worktreeBox: CGFloat = 28
        /// 6pt — worktree icon box corner radius
        public static let worktreeBoxRadius: CGFloat = 6
    }

    // MARK: - Sizes

    public enum Size {
        /// 36pt — project rail avatar circle
        public static let avatar: CGFloat = 36
        /// 16pt — avatar icon font size
        public static let avatarFont: CGFloat = 16
        /// 13pt — font picker preview size
        public static let fontPreview: CGFloat = 13
        /// 10pt — theme swatch circle
        public static let swatch: CGFloat = 10
        /// 20pt — theme preview bar height
        public static let previewBar: CGFloat = 20
    }

    // MARK: - Typography

    public enum Font {
        /// Section header (e.g., "Worktrees") — 11pt bold, uppercase with tracking
        public static let sectionTitle = SwiftUI.Font.system(size: 11, weight: .bold)
        /// Project header name — 14pt bold
        public static let projectTitle = SwiftUI.Font.system(size: 14, weight: .bold)
        /// Worktree row name — 13.5pt semibold
        public static let rowTitle = SwiftUI.Font.system(size: 13.5, weight: .semibold)
        /// Window row name — 12.5pt regular
        public static let windowTitle = SwiftUI.Font.system(size: 12.5)
        /// Small labels, icons, branch icon — 12pt
        public static let label = SwiftUI.Font.caption
        /// Smallest labels (project name under avatar) — 11pt
        public static let caption = SwiftUI.Font.caption2
        /// Badge text — 9.5pt semibold
        public static let badgeText = SwiftUI.Font.system(size: 9.5, weight: .semibold)
        /// Badge count text
        public static let badgeCount = SwiftUI.Font.system(size: 9, weight: .bold, design: .rounded)
        /// Monospace branch name — 11pt
        public static let monoBranch = SwiftUI.Font.system(size: 11, design: .monospaced)
        /// Ahead/behind count / diff stats — 10.5pt mono
        public static let monoSmall = SwiftUI.Font.system(size: 10.5, design: .monospaced)
        /// Keyboard shortcut pills — 10pt mono
        public static let monoShortcut = SwiftUI.Font.system(size: 10, design: .monospaced)
        /// Ahead/behind arrow
        public static let arrowIcon = SwiftUI.Font.system(size: 8)
    }

    // MARK: - Opacity

    public enum Opacity {
        /// 0.08 — subtle highlight (e.g., active window row)
        public static let subtle: Double = 0.08
        /// 0.12 — light highlight (e.g., selected worktree row)
        public static let light: Double = 0.12
        /// 0.2 — medium highlight (e.g., unselected avatar circle)
        public static let medium: Double = 0.2
    }

    // MARK: - Project Avatar Palette

    /// Seven warm/cool duotone pairs (background + foreground) for project letter
    /// avatars. Deterministic per project id so the same project always reads the
    /// same colour across sessions.
    public enum ProjectPalette {
        public struct Pair: Sendable {
            public let background: SwiftUI.Color
            public let foreground: SwiftUI.Color
        }

        public static let pairs: [Pair] = [
            .init(background: SwiftUI.Color(hex: "#1e3d2e"), foreground: SwiftUI.Color(hex: "#7dd3a8")), // mint
            .init(background: SwiftUI.Color(hex: "#3a2a5e"), foreground: SwiftUI.Color(hex: "#c6a0ff")), // violet
            .init(background: SwiftUI.Color(hex: "#1e3a4a"), foreground: SwiftUI.Color(hex: "#7cb0ff")), // sky
            .init(background: SwiftUI.Color(hex: "#4a1f2a"), foreground: SwiftUI.Color(hex: "#ff8a9e")), // rose
            .init(background: SwiftUI.Color(hex: "#3d351e"), foreground: SwiftUI.Color(hex: "#e6b450")), // amber
            .init(background: SwiftUI.Color(hex: "#2a2620"), foreground: SwiftUI.Color(hex: "#c9b991")), // sand
            .init(background: SwiftUI.Color(hex: "#2d1e3d"), foreground: SwiftUI.Color(hex: "#b092e6")), // lilac
        ]

        /// Stable index derived from the first, middle, and last bytes of the
        /// UUID — avoids `hashValue`, which is unstable across processes.
        public static func pair(for id: UUID) -> Pair {
            let u = id.uuid
            let sum = Int(u.0) &+ Int(u.4) &+ Int(u.8) &+ Int(u.12)
            return pairs[abs(sum) % pairs.count]
        }
    }
}

// MARK: - Hex Color convenience

extension SwiftUI.Color {
    /// Parse an sRGB hex colour (e.g. `#7dd3a8`). Internal helper for the palette.
    init(hex: String) {
        let c = nsColor(hex: hex)
        self.init(
            .sRGB,
            red: Double(c.redComponent),
            green: Double(c.greenComponent),
            blue: Double(c.blueComponent),
            opacity: Double(c.alphaComponent)
        )
    }
}

// MARK: - Hex Color Helper (package-internal)

/// Converts a hex color string to NSColor. Used by sidebar and settings views.
func nsColor(hex: String) -> NSColor {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)

    let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
    let b = CGFloat(rgb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
}
