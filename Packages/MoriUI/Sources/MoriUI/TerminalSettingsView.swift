import SwiftUI
import MoriCore

/// SwiftUI settings panel for terminal appearance (font, theme, cursor).
/// Adapts its own appearance to match the currently selected terminal theme.
public struct TerminalSettingsView: View {
    @Binding var settings: TerminalSettings
    var onChanged: () -> Void

    @State private var fontSearch = ""

    public init(settings: Binding<TerminalSettings>, onChanged: @escaping () -> Void) {
        self._settings = settings
        self.onChanged = onChanged
    }

    private var theme: TerminalTheme { settings.theme }
    private var bg: Color { Color(nsColor: nsColor(hex: theme.background)) }
    private var fg: Color { Color(nsColor: nsColor(hex: theme.foreground)) }
    private var dimFg: Color { fg.opacity(0.6) }
    private var surfaceBg: Color { Color(nsColor: nsColor(hex: theme.background)).opacity(0.85) }
    private var accentColor: Color { Color(nsColor: nsColor(hex: theme.ansi[4])) } // blue

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MoriTokens.Spacing.xl) {
                section("Font") {
                    fontSearchField
                    fontPicker
                    fontSizeSlider
                }

                section("Theme") {
                    themeGrid
                    themePreview
                }

                section("Cursor") {
                    cursorStylePicker
                }

                restoreDefaultsButton
            }
            .padding(MoriTokens.Spacing.xl)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380, idealHeight: 480)
        .background(bg)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    // MARK: - Section

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: MoriTokens.Spacing.lg) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dimFg)

            VStack(alignment: .leading, spacing: MoriTokens.Spacing.lg) {
                content()
            }
            .padding(MoriTokens.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: MoriTokens.Radius.medium)
                    .fill(fg.opacity(0.06))
            )
        }
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
                .foregroundStyle(fg)
            Slider(value: $settings.fontSize, in: 8...28, step: 1)
                .tint(accentColor)
            Text("\(Int(settings.fontSize)) pt")
                .monospacedDigit()
                .foregroundStyle(dimFg)
                .frame(width: 40, alignment: .trailing)
        }
        .onChange(of: settings.fontSize) { _, _ in onChanged() }
    }

    // MARK: - Theme

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: MoriTokens.Spacing.lg)]

    @ViewBuilder
    private var themeGrid: some View {
        LazyVGrid(columns: columns, spacing: MoriTokens.Spacing.lg) {
            ForEach(TerminalTheme.builtIn) { t in
                themeCard(t, isSelected: t.name == settings.themeName)
                    .onTapGesture {
                        settings.themeName = t.name
                        onChanged()
                    }
            }
        }
    }

    @ViewBuilder
    private func themeCard(_ t: TerminalTheme, isSelected: Bool) -> some View {
        VStack(spacing: MoriTokens.Spacing.sm) {
            // Mini terminal preview
            RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                .fill(Color(nsColor: nsColor(hex: t.background)))
                .frame(height: 40)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach([t.ansi[1], t.ansi[2], t.ansi[3]], id: \.self) { hex in
                            Circle()
                                .fill(Color(nsColor: nsColor(hex: hex)))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(6)
                }
                .overlay(alignment: .center) {
                    Text("Aa")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(nsColor: nsColor(hex: t.foreground)))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                        .strokeBorder(isSelected ? accentColor : .clear, lineWidth: 2)
                )

            Text(t.name)
                .font(.caption)
                .foregroundStyle(isSelected ? accentColor : fg)
                .lineLimit(1)
        }
        .padding(MoriTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.medium)
                .fill(isSelected ? accentColor.opacity(0.1) : .clear)
        )
    }

    @ViewBuilder
    private var themePreview: some View {
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
                .strokeBorder(fg.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Cursor

    @ViewBuilder
    private var cursorStylePicker: some View {
        HStack(spacing: MoriTokens.Spacing.lg) {
            ForEach(CursorStyle.allCases, id: \.self) { style in
                cursorOption(style, isSelected: settings.cursorStyle == style)
                    .onTapGesture {
                        settings.cursorStyle = style
                        onChanged()
                    }
            }
        }
    }

    @ViewBuilder
    private func cursorOption(_ style: CursorStyle, isSelected: Bool) -> some View {
        VStack(spacing: MoriTokens.Spacing.sm) {
            // Visual cursor preview
            ZStack {
                RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                    .fill(Color(nsColor: nsColor(hex: theme.background)))
                    .frame(width: 36, height: 28)

                cursorShape(style)
            }
            .overlay(
                RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                    .strokeBorder(isSelected ? accentColor : fg.opacity(0.15), lineWidth: 1)
            )

            Text(style.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(isSelected ? accentColor : dimFg)
        }
        .padding(MoriTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.medium)
                .fill(isSelected ? accentColor.opacity(0.1) : .clear)
        )
    }

    @ViewBuilder
    private func cursorShape(_ style: CursorStyle) -> some View {
        let cursorColor = Color(nsColor: nsColor(hex: theme.cursor))
        switch style {
        case .block:
            Rectangle()
                .fill(cursorColor)
                .frame(width: 10, height: 16)
        case .underline:
            VStack {
                Spacer()
                Rectangle()
                    .fill(cursorColor)
                    .frame(width: 10, height: 2)
            }
            .frame(width: 10, height: 16)
        case .bar:
            HStack {
                Rectangle()
                    .fill(cursorColor)
                    .frame(width: 2, height: 16)
                Spacer()
            }
            .frame(width: 10, height: 16)
        }
    }

    // MARK: - Restore Defaults

    @ViewBuilder
    private var restoreDefaultsButton: some View {
        HStack {
            Spacer()
            Button {
                settings = TerminalSettings()
                onChanged()
            } label: {
                Text("Restore Defaults")
                    .font(.caption)
                    .foregroundStyle(dimFg)
                    .padding(.horizontal, MoriTokens.Spacing.xl)
                    .padding(.vertical, MoriTokens.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                            .strokeBorder(fg.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
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

// nsColor(hex:) is defined in DesignTokens.swift (package-internal)
