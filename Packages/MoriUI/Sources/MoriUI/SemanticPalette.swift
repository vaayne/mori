import Foundation

/// A plain sRGB color triple with components in `0...1`.
///
/// Deliberately free of AppKit/SwiftUI: this file is pure color math so it can
/// run in tests and on any platform. The app target owns `NSColor` ↔ `RGB`
/// conversion at the boundary and never leaks a UI type in here.
public struct RGB: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

// MARK: - WCAG luminance & contrast

extension RGB {
    /// sRGB → linear for a single channel (WCAG 2.x transfer function).
    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance in `0...1`.
    public var relativeLuminance: Double {
        0.2126 * RGB.linearize(r)
            + 0.7152 * RGB.linearize(g)
            + 0.0722 * RGB.linearize(b)
    }

    /// Linear interpolation toward `other`. `t = 0` is `self`, `t = 1` is `other`.
    func mixed(with other: RGB, t: Double) -> RGB {
        RGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }
}

/// WCAG contrast ratio between two colors: `(L1 + 0.05) / (L2 + 0.05)` where
/// `L1` is the lighter luminance. Ranges from `1` (identical) to `21` (black on white).
public func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let la = a.relativeLuminance
    let lb = b.relativeLuminance
    let lighter = max(la, lb)
    let darker = min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)
}

// MARK: - Contrast guardrail

/// The minimum contrast a semantic color must hold against the background.
///
/// 3.0, not the 4.5 WCAG demands for body text: these colors paint badges,
/// icons, and status dots — large, non-textual UI where 3.0 (WCAG's threshold
/// for graphical objects and large text) keeps them legible without washing out
/// the theme's character.
public let semanticMinContrast: Double = 3.0

/// Ceiling on how far a slot may be dragged toward the foreground while chasing
/// contrast. Past ~60% the result stops reading as the theme's color and starts
/// looking like a muted foreground tint, which defeats the point of deriving
/// from the theme at all — so we stop and accept a best-effort blend.
public let semanticMaxBlend: Double = 0.60

/// Step size for the blend search. Small enough to keep the boost subtle,
/// coarse enough to terminate quickly.
private let semanticBlendStep: Double = 0.05

/// Nudge `color` toward `foreground` until it clears `semanticMinContrast`
/// against `background`, searching in `semanticBlendStep` increments up to
/// `semanticMaxBlend`.
///
/// Returns the first blend that passes. If even the `semanticMaxBlend` mix
/// falls short (e.g. a background whose luminance is too close to the
/// foreground's for any mix to help), returns that capped mix as a best effort
/// rather than looping forever.
public func ensureContrast(
    _ color: RGB,
    against background: RGB,
    toward foreground: RGB
) -> RGB {
    if contrastRatio(color, background) >= semanticMinContrast {
        return color
    }

    var t = semanticBlendStep
    while t <= semanticMaxBlend {
        let candidate = color.mixed(with: foreground, t: t)
        if contrastRatio(candidate, background) >= semanticMinContrast {
            return candidate
        }
        t += semanticBlendStep
    }

    // Best effort: cap the blend so we never wash the color out entirely.
    return color.mixed(with: foreground, t: semanticMaxBlend)
}

// MARK: - Semantic palette

/// Semantic UI colors derived from a terminal theme, one slot per status role.
public struct SemanticPalette: Sendable, Equatable {
    public var error: RGB
    public var success: RGB
    public var warning: RGB
    public var attention: RGB
    public var info: RGB
    public var active: RGB

    public init(
        error: RGB,
        success: RGB,
        warning: RGB,
        attention: RGB,
        info: RGB,
        active: RGB
    ) {
        self.error = error
        self.success = success
        self.warning = warning
        self.attention = attention
        self.info = info
        self.active = active
    }

    /// Derive the semantic palette from a theme's background, foreground, and
    /// 16-color ANSI table.
    ///
    /// Returns `nil` when `ansi` has fewer than 16 entries — the theme lacks a
    /// full palette and the caller should fall back to system colors rather
    /// than index into a short table.
    ///
    /// Slot → ANSI mapping (standard xterm indices):
    /// - `error`     ← 1  (red)
    /// - `success`   ← 2  (green)
    /// - `warning`   ← 3  (yellow)
    /// - `attention` ← 11 (bright yellow)
    /// - `info`      ← 4  (blue)
    /// - `active`    ← 4  (blue) — intentionally shares `info`'s source so the
    ///   focus/active accent matches tmux's active-pane border color.
    ///
    /// Every slot is passed through `ensureContrast` so a low-contrast theme
    /// color (dark blue on a dark background, say) still reads against the chrome.
    public static func derive(background: RGB, foreground: RGB, ansi: [RGB]) -> SemanticPalette? {
        guard ansi.count >= 16 else { return nil }

        func slot(_ index: Int) -> RGB {
            ensureContrast(ansi[index], against: background, toward: foreground)
        }

        return SemanticPalette(
            error: slot(1),
            success: slot(2),
            warning: slot(3),
            attention: slot(11),
            info: slot(4),
            active: slot(4)
        )
    }
}
