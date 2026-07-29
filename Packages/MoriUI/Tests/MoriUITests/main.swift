import Foundation
import MoriUI

// MARK: - Helpers

/// Parse a `#rrggbb` hex string into an `RGB` for readable test fixtures.
func hex(_ s: String) -> RGB {
    var str = s
    if str.hasPrefix("#") { str.removeFirst() }
    let v = UInt32(str, radix: 16) ?? 0
    return RGB(
        r: Double((v >> 16) & 0xFF) / 255.0,
        g: Double((v >> 8) & 0xFF) / 255.0,
        b: Double(v & 0xFF) / 255.0
    )
}

/// Gruvbox Dark (medium) — a real 16-color ANSI palette used as a regular-theme fixture.
let gruvboxBackground = hex("#282828")
let gruvboxForeground = hex("#ebdbb2")
let gruvboxAnsi: [RGB] = [
    hex("#282828"), // 0  black
    hex("#cc241d"), // 1  red
    hex("#98971a"), // 2  green
    hex("#d79921"), // 3  yellow
    hex("#458588"), // 4  blue
    hex("#b16286"), // 5  magenta
    hex("#689d6a"), // 6  cyan
    hex("#a89984"), // 7  white
    hex("#928374"), // 8  bright black
    hex("#fb4934"), // 9  bright red
    hex("#b8bb26"), // 10 bright green
    hex("#fabd2f"), // 11 bright yellow
    hex("#83a598"), // 12 bright blue
    hex("#d3869b"), // 13 bright magenta
    hex("#8ec07c"), // 14 bright cyan
    hex("#ebdbb2"), // 15 bright white
]

// MARK: - Contrast ratio: known values

func testContrastBlackOnWhite() {
    // The canonical WCAG anchor: pure black vs pure white is exactly 21:1.
    assertApprox(contrastRatio(hex("#000000"), hex("#ffffff")), 21.0, tolerance: 1e-9)
    // Order-independent.
    assertApprox(contrastRatio(hex("#ffffff"), hex("#000000")), 21.0, tolerance: 1e-9)
}

func testContrastIdenticalIsOne() {
    assertApprox(contrastRatio(hex("#3a6ea5"), hex("#3a6ea5")), 1.0, tolerance: 1e-9)
}

func testRelativeLuminanceEndpoints() {
    assertApprox(hex("#ffffff").relativeLuminance, 1.0, tolerance: 1e-9)
    assertApprox(hex("#000000").relativeLuminance, 0.0, tolerance: 1e-9)
}

// MARK: - derive: regular theme passthrough

func testDeriveGruvboxPassthrough() {
    let palette = SemanticPalette.derive(
        background: gruvboxBackground,
        foreground: gruvboxForeground,
        ansi: gruvboxAnsi
    )
    assertNotNil(palette)
    guard let palette else { return }

    // Slots that already clear the 3.0 guardrail against the background pass
    // through untouched — output equals the source ANSI color exactly.
    assertEqual(palette.success, gruvboxAnsi[2], "green passes through")
    assertEqual(palette.warning, gruvboxAnsi[3], "yellow passes through")
    assertEqual(palette.attention, gruvboxAnsi[11], "bright yellow passes through")
    assertEqual(palette.info, gruvboxAnsi[4], "blue passes through")
    assertEqual(palette.active, gruvboxAnsi[4], "blue passes through")

    // active deliberately shares blue with info (tmux active-border source).
    assertEqual(palette.active, palette.info, "active and info share the blue source")

    // Each passing slot genuinely clears the guardrail.
    for c in [palette.success, palette.warning, palette.attention, palette.info] {
        assertTrue(contrastRatio(c, gruvboxBackground) >= semanticMinContrast)
    }
}

func testDeriveGruvboxRedIsNudged() {
    // Gruvbox's neutral red (#cc241d) sits just under 3.0 on #282828 (~2.69),
    // so it is the one slot the guardrail nudges toward the foreground.
    let palette = SemanticPalette.derive(
        background: gruvboxBackground,
        foreground: gruvboxForeground,
        ansi: gruvboxAnsi
    )!

    // Source fails the guardrail; result must clear it and differ from source.
    assertTrue(contrastRatio(gruvboxAnsi[1], gruvboxBackground) < semanticMinContrast, "red source is below guardrail")
    assertTrue(contrastRatio(palette.error, gruvboxBackground) >= semanticMinContrast, "boosted red clears guardrail")
    assertNotEqual(palette.error, gruvboxAnsi[1], "red was adjusted")

    // Recover the blend fraction from the green channel and confirm it stayed
    // well under the 60% ceiling (a small nudge suffices for a near-miss).
    let src = gruvboxAnsi[1].g
    let fg = gruvboxForeground.g
    let t = (palette.error.g - src) / (fg - src)
    assertTrue(t > 0.0 && t <= semanticMaxBlend, "blend fraction within (0, 0.60]")
}

// MARK: - derive: low-contrast slot boosted below the ceiling

func testDeriveBoostsLowContrastBlue() {
    // Near-black background + a dark blue ANSI[4] that fails the guardrail.
    let bg = hex("#0a0a0a")
    let fg = hex("#e0e0e0")
    var ansi = [RGB](repeating: hex("#0a0a0a"), count: 16)
    ansi[4] = hex("#202080") // dark blue, ~1.5:1 on near-black

    let palette = SemanticPalette.derive(background: bg, foreground: fg, ansi: ansi)!

    assertTrue(contrastRatio(ansi[4], bg) < semanticMinContrast, "dark blue source fails guardrail")
    assertNotEqual(palette.info, ansi[4], "info was boosted")
    assertTrue(contrastRatio(palette.info, bg) >= semanticMinContrast, "boosted info clears guardrail")

    // Blend fraction (recovered from blue channel) is a genuine pass strictly
    // below the ceiling — not the best-effort cap.
    let src = ansi[4].b
    let fgb = fg.b
    let t = (palette.info.b - src) / (fgb - src)
    assertTrue(t > 0.0 && t < semanticMaxBlend, "boost landed below the 60% ceiling")
}

// MARK: - derive: extreme theme falls back to best-effort without looping

func testDeriveAllBlackBestEffort() {
    // bg == fg == black, all-black palette: no blend can raise contrast, so the
    // guardrail must terminate at the 60% cap rather than spin forever.
    let black = hex("#000000")
    let ansi = [RGB](repeating: black, count: 16)

    let palette = SemanticPalette.derive(background: black, foreground: black, ansi: ansi)
    assertNotNil(palette)
    guard let palette else { return }

    // Every slot is the capped best effort — still black, still below guardrail.
    assertEqual(palette.error, black)
    assertEqual(palette.success, black)
    assertEqual(palette.info, black)
    assertTrue(contrastRatio(palette.error, black) < semanticMinContrast, "best effort still under guardrail")
}

// MARK: - derive: missing palette

func testDeriveNilWhenAnsiTooShort() {
    let short = [RGB](repeating: hex("#ffffff"), count: 15)
    assertNil(SemanticPalette.derive(background: gruvboxBackground, foreground: gruvboxForeground, ansi: short))
}

func testDeriveNilWhenAnsiEmpty() {
    assertNil(SemanticPalette.derive(background: gruvboxBackground, foreground: gruvboxForeground, ansi: []))
}

func testDeriveNonNilAtExactly16() {
    let ansi = [RGB](repeating: hex("#ffffff"), count: 16)
    assertNotNil(SemanticPalette.derive(background: hex("#000000"), foreground: hex("#000000"), ansi: ansi))
}

// MARK: - ensureContrast: direct guardrail behavior

func testEnsureContrastLeavesPassingColorUntouched() {
    let bg = hex("#000000")
    let white = hex("#ffffff")
    assertEqual(ensureContrast(white, against: bg, toward: bg), white, "already high-contrast color is unchanged")
}

func testEnsureContrastCapsAtMaxBlend() {
    // Impossible target: never reaches 3.0, so returns the capped best effort.
    // Mixing black toward black is black regardless of the blend fraction.
    let black = hex("#000000")
    let result = ensureContrast(black, against: black, toward: black)
    assertEqual(result, black)
}

// MARK: - Run

testContrastBlackOnWhite()
testContrastIdenticalIsOne()
testRelativeLuminanceEndpoints()
testDeriveGruvboxPassthrough()
testDeriveGruvboxRedIsNudged()
testDeriveBoostsLowContrastBlue()
testDeriveAllBlackBestEffort()
testDeriveNilWhenAnsiTooShort()
testDeriveNilWhenAnsiEmpty()
testDeriveNonNilAtExactly16()
testEnsureContrastLeavesPassingColorUntouched()
testEnsureContrastCapsAtMaxBlend()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
