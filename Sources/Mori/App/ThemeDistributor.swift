import AppKit
import MoriTerminal

/// A window or view that repaints its chrome to match the current Ghostty terminal theme.
///
/// Conform and register with `ThemeDistributor` to receive the current theme on
/// registration and on every later theme change. Opaque chrome windows can lean on
/// the default `applyTheme` — expose the window through `themedWindow` and it syncs
/// the appearance and background. Surfaces with bespoke chrome (tinted planes, glass,
/// translucency, per-key-window state) override `applyTheme` and return `nil` from
/// `themedWindow` to signal they paint themselves.
@MainActor
protocol ThemedSurface: AnyObject {
    var themedWindow: NSWindow? { get }
    func applyTheme(_ themeInfo: GhosttyThemeInfo)
}

extension ThemedSurface {
    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        guard let window = themedWindow else { return }
        window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window.backgroundColor = themeInfo.background
    }
}

/// Bridges a raw `NSWindow` — one without a controller object that can conform to
/// `ThemedSurface` itself (the main workspace window, the settings window) — into the
/// theme pipeline. Retain it for as long as the window should track the theme; the
/// distributor holds only a weak reference.
@MainActor
final class WindowThemedSurface: ThemedSurface {
    private let paint: @MainActor (GhosttyThemeInfo) -> Void

    init(paint: @escaping @MainActor (GhosttyThemeInfo) -> Void) {
        self.paint = paint
    }

    var themedWindow: NSWindow? { nil }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        paint(themeInfo)
    }
}

/// Fans the resolved Ghostty theme out to every registered surface.
///
/// The single source of theme truth is `GhosttyApp.shared.themeInfo`; call
/// `broadcast(_:)` whenever it changes (config reload, system dark/light flip) to
/// repaint every surface at once. Surfaces register once at creation and are held
/// weakly, so they drop out automatically when deallocated. Registering after the
/// first broadcast applies the current theme immediately, so lazily-created panels
/// open already themed without any caller threading the theme through.
@MainActor
final class ThemeDistributor {
    private let surfaces = NSHashTable<AnyObject>.weakObjects()
    private var currentTheme: GhosttyThemeInfo?

    func register(_ surface: ThemedSurface) {
        surfaces.add(surface)
        if let currentTheme {
            surface.applyTheme(currentTheme)
        }
    }

    func broadcast(_ themeInfo: GhosttyThemeInfo) {
        currentTheme = themeInfo
        for case let surface as ThemedSurface in surfaces.allObjects {
            surface.applyTheme(themeInfo)
        }
    }
}
