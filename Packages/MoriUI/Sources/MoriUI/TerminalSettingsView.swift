import SwiftUI
import MoriCore

/// SwiftUI settings panel for terminal appearance (font, theme, cursor).
/// Designed to be hosted in a preferences window (Cmd+,).
public struct TerminalSettingsView: View {
    @Binding var settings: TerminalSettings
    var onChanged: () -> Void

    public init(settings: Binding<TerminalSettings>, onChanged: @escaping () -> Void) {
        self._settings = settings
        self.onChanged = onChanged
    }

    public var body: some View {
        Form {
            Section("Font") {
                fontPicker
                fontSizeSlider
            }

            Section("Theme") {
                themePicker
                themePreview
            }

            Section("Cursor") {
                cursorStylePicker
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }

    // MARK: - Font

    @ViewBuilder
    private var fontPicker: some View {
        Picker("Family", selection: $settings.fontFamily) {
            ForEach(monospacedFontFamilies, id: \.self) { family in
                Text(family)
                    .font(.custom(family, size: 13))
                    .tag(family)
            }
        }
        .onChange(of: settings.fontFamily) { _, _ in onChanged() }
    }

    @ViewBuilder
    private var fontSizeSlider: some View {
        HStack {
            Text("Size")
            Slider(value: $settings.fontSize, in: 8...28, step: 1)
            Text("\(Int(settings.fontSize)) pt")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .onChange(of: settings.fontSize) { _, _ in onChanged() }
    }

    // MARK: - Theme

    @ViewBuilder
    private var themePicker: some View {
        Picker("Color Scheme", selection: $settings.themeName) {
            ForEach(TerminalTheme.builtIn) { theme in
                HStack(spacing: 6) {
                    themeSwatches(theme)
                    Text(theme.name)
                }
                .tag(theme.name)
            }
        }
        .onChange(of: settings.themeName) { _, _ in onChanged() }
    }

    @ViewBuilder
    private var themePreview: some View {
        let theme = settings.theme
        HStack(spacing: 0) {
            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(Color(nsColor: nsColor(hex: theme.ansi[i])))
                    .frame(height: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func themeSwatches(_ theme: TerminalTheme) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.background)))
                .frame(width: 10, height: 10)
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.foreground)))
                .frame(width: 10, height: 10)
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.ansi[4])))  // blue
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Cursor

    @ViewBuilder
    private var cursorStylePicker: some View {
        Picker("Style", selection: $settings.cursorStyle) {
            Text("Block").tag(CursorStyle.block)
            Text("Underline").tag(CursorStyle.underline)
            Text("Bar").tag(CursorStyle.bar)
        }
        .pickerStyle(.segmented)
        .onChange(of: settings.cursorStyle) { _, _ in onChanged() }
    }

    // MARK: - Helpers

    private var monospacedFontFamilies: [String] {
        let manager = NSFontManager.shared
        let allFamilies = manager.availableFontFamilies
        return allFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family),
                  let firstMember = members.first,
                  let fontName = firstMember[0] as? String,
                  let font = NSFont(name: fontName, size: 13)
            else { return false }
            return font.isFixedPitch
        }.sorted()
    }
}

// Local hex-to-NSColor helper (avoids cross-module extension conflicts)
private func nsColor(hex: String) -> NSColor {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)

    let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
    let b = CGFloat(rgb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
}
