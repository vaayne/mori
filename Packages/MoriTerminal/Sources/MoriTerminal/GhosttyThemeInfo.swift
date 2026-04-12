#if os(macOS)
import AppKit
import GhosttyKit

/// Resolved theme colors extracted from ghostty's config.
/// Queried once at startup via `ghostty_config_get` before the config is consumed.
public struct GhosttyThemeInfo: Sendable {
    public enum BackgroundBlur: Sendable, Equatable {
        case disabled
        case radius(Int)
        case macosGlassRegular
        case macosGlassClear

        public var isEnabled: Bool {
            switch self {
            case .disabled: false
            default: true
            }
        }

        public var isGlassStyle: Bool {
            switch self {
            case .macosGlassRegular, .macosGlassClear: true
            default: false
            }
        }

        static func from(cValue: Int16) -> BackgroundBlur {
            switch cValue {
            case 0:
                .disabled
            case -1:
                if #available(macOS 26.0, *) {
                    .macosGlassRegular
                } else {
                    .disabled
                }
            case -2:
                if #available(macOS 26.0, *) {
                    .macosGlassClear
                } else {
                    .disabled
                }
            default:
                .radius(Int(cValue))
            }
        }
    }

    public let background: NSColor
    public let foreground: NSColor
    /// ANSI palette (16 standard colors, indices 0-15).
    public let palette: [NSColor]
    public let isDark: Bool
    public let backgroundOpacity: Double
    public let backgroundBlur: BackgroundBlur

    public var effectiveBackground: NSColor {
        background.withAlphaComponent(backgroundOpacity)
    }

    public var usesTransparentWindowBackground: Bool {
        backgroundOpacity < 1 || backgroundBlur.isGlassStyle
    }

    /// Default fallback when config cannot be queried.
    public static let fallback = GhosttyThemeInfo(
        background: .black,
        foreground: .white,
        palette: (0..<16).map { _ in .gray },
        isDark: true,
        backgroundOpacity: 1,
        backgroundBlur: .disabled
    )

    /// Query theme colors from a finalized ghostty config.
    @MainActor
    static func from(config: ghostty_config_t) -> GhosttyThemeInfo {
        let bg = queryColor(config, key: "background") ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let fg = queryColor(config, key: "foreground") ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let backgroundOpacity = queryDouble(config, key: "background-opacity") ?? 1
        let backgroundBlur = queryBackgroundBlur(config, key: "background-blur") ?? .disabled

        // Query palette — ghostty_config_palette_s contains a 256-element C array
        // which Swift imports as a massive tuple. Use withUnsafePointer to access by index.
        var paletteStruct = ghostty_config_palette_s()
        let hasPalette = withUnsafeMutablePointer(to: &paletteStruct) { ptr in
            let key = "palette"
            return ghostty_config_get(config, ptr, key, UInt(key.count))
        }

        var palette: [NSColor] = []
        if hasPalette {
            withUnsafePointer(to: &paletteStruct.colors) { tuplePtr in
                tuplePtr.withMemoryRebound(to: ghostty_config_color_s.self, capacity: 256) { arrayPtr in
                    for i in 0..<16 {
                        let c = arrayPtr[i]
                        palette.append(NSColor(
                            srgbRed: CGFloat(c.r) / 255.0,
                            green: CGFloat(c.g) / 255.0,
                            blue: CGFloat(c.b) / 255.0,
                            alpha: 1.0
                        ))
                    }
                }
            }
        } else {
            palette = (0..<16).map { _ in .gray }
        }

        // Determine dark/light from background luminance
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        (bg.usingColorSpace(.sRGB) ?? bg).getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        return GhosttyThemeInfo(
            background: bg,
            foreground: fg,
            palette: palette,
            isDark: luminance < 0.5,
            backgroundOpacity: max(0.001, min(backgroundOpacity, 1)),
            backgroundBlur: backgroundBlur
        )
    }

    /// Convert a color to hex string (#rrggbb).
    public static func hexString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func queryColor(_ config: ghostty_config_t, key: String) -> NSColor? {
        var color = ghostty_config_color_s(r: 0, g: 0, b: 0)
        let success = withUnsafeMutablePointer(to: &color) { ptr in
            ghostty_config_get(config, ptr, key, UInt(key.count))
        }
        guard success else { return nil }
        return NSColor(
            srgbRed: CGFloat(color.r) / 255.0,
            green: CGFloat(color.g) / 255.0,
            blue: CGFloat(color.b) / 255.0,
            alpha: 1.0
        )
    }

    private static func queryDouble(_ config: ghostty_config_t, key: String) -> Double? {
        var value: Double = 0
        let success = withUnsafeMutablePointer(to: &value) { ptr in
            ghostty_config_get(config, ptr, key, UInt(key.count))
        }
        return success ? value : nil
    }

    private static func queryBackgroundBlur(_ config: ghostty_config_t, key: String) -> BackgroundBlur? {
        var value: Int16 = 0
        let success = withUnsafeMutablePointer(to: &value) { ptr in
            ghostty_config_get(config, ptr, key, UInt(key.count))
        }
        return success ? BackgroundBlur.from(cValue: value) : nil
    }
}
#endif
