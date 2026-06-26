#if os(macOS)
import AppKit
import GhosttyKit

/// Light/dark color scheme, mirroring ghostty's `ghostty_color_scheme_e`.
public enum GhosttyColorScheme: Sendable {
    case light
    case dark

    var cValue: ghostty_color_scheme_e {
        self == .dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }

    /// The current system appearance, resolved from `NSApp.effectiveAppearance`.
    @MainActor
    public static var system: GhosttyColorScheme {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }
}

/// Parses ghostty's split light/dark `theme` syntax (`theme = light:Foo,dark:Bar`).
///
/// libghostty resolves a split theme to a single set of colors at config-finalize
/// time based on a private conditional state that defaults to light, and exposes no
/// C API to query the dark variant from a bare config. So to render Mori's own chrome
/// (sidebar, windows, panels, tmux) in the appearance the user is actually in, we
/// resolve the variant name ourselves and force it onto an extraction config.
public enum GhosttyThemeSpec {
    /// A parsed light/dark split theme.
    public struct Split: Sendable, Equatable {
        public var light: String
        public var dark: String

        public init(light: String, dark: String) {
            self.light = light
            self.dark = dark
        }
    }

    /// Parse a raw `theme` config value as a light/dark split (`light:Foo,dark:Bar`).
    /// Returns nil when neither a `light` nor `dark` key is present (single theme).
    /// A missing side mirrors the present one so both fields are always populated.
    public static func parseSplit(_ rawValue: String) -> Split? {
        var light: String?
        var dark: String?

        for token in rawValue.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            for prefix in ["light:", "light="] where lower.hasPrefix(prefix) {
                light = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            for prefix in ["dark:", "dark="] where lower.hasPrefix(prefix) {
                dark = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard light != nil || dark != nil else { return nil }
        let l = light ?? dark ?? ""
        let d = dark ?? light ?? ""
        return Split(light: l, dark: d)
    }

    /// Build the ghostty `theme` value for a light/dark split.
    public static func splitValue(light: String, dark: String) -> String {
        "light:\(light),dark:\(dark)"
    }

    /// Resolve a raw `theme` config value to a single theme name for `scheme`.
    /// Returns nil when the value is not a light/dark split — callers should then
    /// use the config's own resolution (single theme or ghostty default).
    static func resolveSplit(_ rawValue: String, scheme: GhosttyColorScheme) -> String? {
        guard let split = parseSplit(rawValue) else { return nil }
        return scheme == .dark ? split.dark : split.light
    }
}
#endif
