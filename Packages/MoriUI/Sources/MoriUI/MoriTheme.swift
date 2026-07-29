import SwiftUI

/// Observable store backing the six semantic color slots exposed through
/// `MoriTokens.Color`.
///
/// Why a `@MainActor` static `shared` singleton rather than an `Environment`
/// injection: the semantic slots on `MoriTokens.Color` form a static API read
/// from ~100 SwiftUI call sites, none of which have (or want) a view/environment
/// handle. Observation registers a dependency on any `@Observable` property read
/// during a `body` evaluation, so a `body` that reads a slot — which forwards to
/// `MoriTheme.shared` — is invalidated and re-rendered when `apply`
/// mutates that slot, exactly as an `@Environment` value would. The singleton is
/// therefore semantically equivalent to injection here while keeping the
/// migration surface at zero: no call site changes.
@MainActor
@Observable
public final class MoriTheme {
    public static let shared = MoriTheme()

    // System-color defaults. Kept as the single source of truth so the initial
    // state and `reset()` cannot drift apart. These match the values MoriTokens
    // shipped before the palette store existed, so an un-applied theme paints
    // pixel-for-pixel identically.
    private static let defaultError: Color = .red
    private static let defaultSuccess: Color = .green
    private static let defaultWarning: Color = .orange
    private static let defaultAttention: Color = .yellow
    private static let defaultInfo: Color = .blue
    private static let defaultActive: Color = .accentColor

    public private(set) var error: Color = MoriTheme.defaultError
    public private(set) var success: Color = MoriTheme.defaultSuccess
    public private(set) var warning: Color = MoriTheme.defaultWarning
    public private(set) var attention: Color = MoriTheme.defaultAttention
    public private(set) var info: Color = MoriTheme.defaultInfo
    public private(set) var active: Color = MoriTheme.defaultActive

    private init() {}

    /// Adopt a theme-derived palette, replacing all six slots.
    public func apply(_ palette: SemanticPalette) {
        error = Color(palette.error)
        success = Color(palette.success)
        warning = Color(palette.warning)
        attention = Color(palette.attention)
        info = Color(palette.info)
        active = Color(palette.active)
    }

    /// Restore the system-color defaults. Callers use this to fall back when a
    /// theme yields no derivable palette (`SemanticPalette.derive` returned nil).
    public func reset() {
        error = MoriTheme.defaultError
        success = MoriTheme.defaultSuccess
        warning = MoriTheme.defaultWarning
        attention = MoriTheme.defaultAttention
        info = MoriTheme.defaultInfo
        active = MoriTheme.defaultActive
    }
}

private extension Color {
    /// Build an sRGB `Color` from a palette triple.
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
