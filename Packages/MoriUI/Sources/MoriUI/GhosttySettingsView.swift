import SwiftUI

/// Settings model representing user-facing ghostty config options.
/// Read from and written to ~/.config/ghostty/config.
public struct GhosttySettingsModel: Equatable {
    public var fontFamily: String
    public var fontSize: Int
    public var theme: String
    public var cursorStyle: String      // block, bar, underline
    public var cursorBlink: Bool
    public var backgroundOpacity: Double
    public var macosOptionAsAlt: String  // true, false, left, right
    public var mouseHideWhileTyping: Bool
    public var copyOnSelect: String      // true, false, clipboard
    public var windowPaddingBalance: Bool
    public var keybinds: [String]

    public init(
        fontFamily: String = "",
        fontSize: Int = 13,
        theme: String = "",
        cursorStyle: String = "block",
        cursorBlink: Bool = true,
        backgroundOpacity: Double = 1.0,
        macosOptionAsAlt: String = "false",
        mouseHideWhileTyping: Bool = false,
        copyOnSelect: String = "false",
        windowPaddingBalance: Bool = false,
        keybinds: [String] = []
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.theme = theme
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.backgroundOpacity = backgroundOpacity
        self.macosOptionAsAlt = macosOptionAsAlt
        self.mouseHideWhileTyping = mouseHideWhileTyping
        self.copyOnSelect = copyOnSelect
        self.windowPaddingBalance = windowPaddingBalance
        self.keybinds = keybinds
    }
}

/// SwiftUI settings panel for ghostty terminal configuration.
/// Reads/writes ~/.config/ghostty/config directly.
public struct GhosttySettingsView: View {
    @Binding var model: GhosttySettingsModel
    var availableThemes: [String]
    var onChanged: () -> Void
    var onOpenConfigFile: () -> Void

    @State private var themeSearch = ""
    @State private var fontSearch = ""

    public init(
        model: Binding<GhosttySettingsModel>,
        availableThemes: [String],
        onChanged: @escaping () -> Void,
        onOpenConfigFile: @escaping () -> Void
    ) {
        self._model = model
        self.availableThemes = availableThemes
        self.onChanged = onChanged
        self.onOpenConfigFile = onOpenConfigFile
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fontSection
                themeSection
                cursorSection
                inputSection
                appearanceSection
                keybindSection
                advancedSection
            }
            .padding(20)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 640)
    }

    // MARK: - Font

    @ViewBuilder
    private var fontSection: some View {
        settingsSection("Font") {
            HStack {
                Text("Family")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g. SF Mono, JetBrains Mono", text: $model.fontFamily)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.fontFamily) { _, _ in onChanged() }
            }

            HStack {
                Text("Size")
                    .frame(width: 80, alignment: .trailing)
                Slider(value: Binding(
                    get: { Double(model.fontSize) },
                    set: { model.fontSize = Int($0) }
                ), in: 8...32, step: 1)
                Text("\(model.fontSize) pt")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            .onChange(of: model.fontSize) { _, _ in onChanged() }
        }
    }

    // MARK: - Theme

    @ViewBuilder
    private var themeSection: some View {
        settingsSection("Theme") {
            HStack {
                Text("Theme")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g. catppuccin-mocha", text: $model.theme)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.theme) { _, _ in onChanged() }
            }

            if !availableThemes.isEmpty {
                TextField("Search themes…", text: $themeSearch)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredThemes, id: \.self) { name in
                            themeRow(name)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func themeRow(_ name: String) -> some View {
        let isSelected = normalizeThemeName(model.theme) == normalizeThemeName(name)
        HStack {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.theme = themeConfigValue(name)
            onChanged()
        }
    }

    private var filteredThemes: [String] {
        guard !themeSearch.isEmpty else { return availableThemes }
        let query = themeSearch.lowercased()
        return availableThemes.filter { $0.lowercased().contains(query) }
    }

    /// Ghostty theme names with spaces use the space in config (e.g., "catppuccin frappe").
    /// File names may use spaces or hyphens — normalize for comparison.
    private func normalizeThemeName(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "-", with: " ")
    }

    /// Convert display name to config value (lowercase with spaces).
    private func themeConfigValue(_ name: String) -> String {
        // Theme file names are the config values — ghostty accepts them as-is
        name
    }

    // MARK: - Cursor

    @ViewBuilder
    private var cursorSection: some View {
        settingsSection("Cursor") {
            HStack {
                Text("Style")
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $model.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.cursorStyle) { _, _ in onChanged() }
            }

            HStack {
                Text("Blink")
                    .frame(width: 80, alignment: .trailing)
                Toggle("", isOn: $model.cursorBlink)
                    .labelsHidden()
                    .onChange(of: model.cursorBlink) { _, _ in onChanged() }
                Spacer()
            }
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSection: some View {
        settingsSection("Input") {
            HStack {
                Text("Option as Alt")
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $model.macosOptionAsAlt) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Left Only").tag("left")
                    Text("Right Only").tag("right")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.macosOptionAsAlt) { _, _ in onChanged() }
            }

            HStack {
                Text("Copy on Select")
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $model.copyOnSelect) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Clipboard").tag("clipboard")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.copyOnSelect) { _, _ in onChanged() }
            }

            HStack {
                Text("Hide Mouse")
                    .frame(width: 80, alignment: .trailing)
                Toggle("While typing", isOn: $model.mouseHideWhileTyping)
                    .onChange(of: model.mouseHideWhileTyping) { _, _ in onChanged() }
                Spacer()
            }
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        settingsSection("Appearance") {
            HStack {
                Text("Opacity")
                    .frame(width: 80, alignment: .trailing)
                Slider(value: $model.backgroundOpacity, in: 0.1...1.0, step: 0.05)
                Text("\(Int(model.backgroundOpacity * 100))%")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            .onChange(of: model.backgroundOpacity) { _, _ in onChanged() }

            HStack {
                Text("Padding")
                    .frame(width: 80, alignment: .trailing)
                Toggle("Balance window padding", isOn: $model.windowPaddingBalance)
                    .onChange(of: model.windowPaddingBalance) { _, _ in onChanged() }
                Spacer()
            }
        }
    }

    // MARK: - Keybinds

    @ViewBuilder
    private var keybindSection: some View {
        settingsSection("Keybinds") {
            if model.keybinds.isEmpty {
                Text("No custom keybinds")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(Array(model.keybinds.enumerated()), id: \.offset) { index, bind in
                    HStack {
                        Text(bind)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.keybinds.remove(at: index)
                            onChanged()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Edit config file to add keybinds")
                .foregroundStyle(.tertiary)
                .font(.caption2)
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedSection: some View {
        VStack(spacing: 12) {
            Button(action: onOpenConfigFile) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("Open Config File")
                }
            }

            Text("~/.config/ghostty/config")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
