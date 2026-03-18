import SwiftUI
import MoriCore

/// SwiftUI settings panel for terminal appearance (font, theme, cursor).
/// Designed to be hosted in a preferences window (Cmd+,).
public struct TerminalSettingsView: View {
    @Binding var settings: TerminalSettings
    var onChanged: () -> Void

    @State private var fontSearch = ""

    public init(settings: Binding<TerminalSettings>, onChanged: @escaping () -> Void) {
        self._settings = settings
        self.onChanged = onChanged
    }

    public var body: some View {
        Form {
            Section("Font") {
                fontSearchField
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

            Section {
                Button("Restore Defaults") {
                    settings = TerminalSettings()
                    onChanged()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380, idealHeight: 480)
    }

    // MARK: - Font

    @ViewBuilder
    private var fontSearchField: some View {
        TextField("Filter fonts…", text: $fontSearch)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
    }

    @ViewBuilder
    private var fontPicker: some View {
        Picker("Family", selection: $settings.fontFamily) {
            ForEach(filteredFontFamilies, id: \.self) { family in
                Text(family)
                    .font(.custom(family, size: MoriTokens.Size.fontPreview))
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
                HStack(spacing: MoriTokens.Spacing.md) {
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
                    .frame(height: MoriTokens.Size.previewBar)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func themeSwatches(_ theme: TerminalTheme) -> some View {
        HStack(spacing: MoriTokens.Spacing.xs) {
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.background)))
                .frame(width: MoriTokens.Size.swatch, height: MoriTokens.Size.swatch)
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.foreground)))
                .frame(width: MoriTokens.Size.swatch, height: MoriTokens.Size.swatch)
            Circle()
                .fill(Color(nsColor: nsColor(hex: theme.ansi[4])))  // blue
                .frame(width: MoriTokens.Size.swatch, height: MoriTokens.Size.swatch)
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

    private var filteredFontFamilies: [String] {
        let all = monospacedFontFamilies
        guard !fontSearch.isEmpty else { return all }
        let query = fontSearch.lowercased()
        return all.filter { $0.lowercased().contains(query) }
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
