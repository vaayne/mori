import SwiftUI
import CoreText
import MoriCore

/// Settings model representing user-facing ghostty config options.
/// Read from and written to ~/.config/ghostty/config.
public enum GhosttyBackgroundBlur: Equatable {
    case disabled
    case standard
    case radius(Int)
    case macosGlassRegular
    case macosGlassClear

    public init(configValue: String) {
        let value = configValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "", "false", "0":
            self = .disabled
        case "true":
            self = .standard
        case "macos-glass-regular":
            self = .macosGlassRegular
        case "macos-glass-clear":
            self = .macosGlassClear
        default:
            if let radius = Int(value), radius > 0 {
                self = .radius(radius)
            } else {
                self = .disabled
            }
        }
    }

    public var configValue: String {
        switch self {
        case .disabled:
            "false"
        case .standard:
            "true"
        case .radius(let value):
            "\(max(1, value))"
        case .macosGlassRegular:
            "macos-glass-regular"
        case .macosGlassClear:
            "macos-glass-clear"
        }
    }

    public var radiusValue: Int {
        switch self {
        case .radius(let value):
            max(1, value)
        case .standard:
            20
        default:
            20
        }
    }
}

public struct GhosttySettingsModel: Equatable {
    public var fontFamily: String
    public var fontSize: Int
    public var theme: String
    public var cursorStyle: String
    public var cursorBlink: Bool
    public var backgroundOpacity: Double
    public var backgroundOpacityCells: Bool
    public var backgroundBlur: GhosttyBackgroundBlur
    public var macosOptionAsAlt: String
    public var mouseHideWhileTyping: Bool
    public var mouseScrollMultiplier: Int
    public var copyOnSelect: String
    public var windowPaddingBalance: Bool
    public var keybinds: [String]

    public init(
        fontFamily: String = "",
        fontSize: Int = 13,
        theme: String = "",
        cursorStyle: String = "block",
        cursorBlink: Bool = true,
        backgroundOpacity: Double = 1.0,
        backgroundOpacityCells: Bool = false,
        backgroundBlur: GhosttyBackgroundBlur = .disabled,
        macosOptionAsAlt: String = "false",
        mouseHideWhileTyping: Bool = false,
        mouseScrollMultiplier: Int = 1,
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
        self.backgroundOpacityCells = backgroundOpacityCells
        self.backgroundBlur = backgroundBlur
        self.macosOptionAsAlt = macosOptionAsAlt
        self.mouseHideWhileTyping = mouseHideWhileTyping
        self.mouseScrollMultiplier = mouseScrollMultiplier
        self.copyOnSelect = copyOnSelect
        self.windowPaddingBalance = windowPaddingBalance
        self.keybinds = keybinds
    }
}

// MARK: - Proxy Settings Model

/// Proxy configuration mode.
public enum ProxyMode: String, Equatable, CaseIterable {
    case system = "system"
    case manual = "manual"
    case none = "none"
}

/// Represents network proxy environment variables applied to all tmux sessions.
public struct ProxySettingsModel: Equatable {
    public var mode: ProxyMode
    public var httpProxy: String
    public var httpsProxy: String
    public var sameForHTTPS: Bool
    public var socksProxy: String
    public var noProxy: String

    public init(
        mode: ProxyMode = .none,
        httpProxy: String = "",
        httpsProxy: String = "",
        sameForHTTPS: Bool = true,
        socksProxy: String = "",
        noProxy: String = ""
    ) {
        self.mode = mode
        self.httpProxy = httpProxy
        self.httpsProxy = httpsProxy
        self.sameForHTTPS = sameForHTTPS
        self.socksProxy = socksProxy
        self.noProxy = noProxy
    }

    /// Resolved HTTPS proxy value (uses HTTP proxy if sameForHTTPS is on).
    public var resolvedHTTPSProxy: String {
        sameForHTTPS ? httpProxy : httpsProxy
    }

    /// The env var names and their resolved values for the current mode.
    public var entries: [(envName: String, value: String)] {
        switch mode {
        case .none:
            return [
                ("http_proxy", ""),
                ("https_proxy", ""),
                ("all_proxy", ""),
                ("no_proxy", ""),
            ]
        case .system, .manual:
            return [
                ("http_proxy", httpProxy),
                ("https_proxy", resolvedHTTPSProxy),
                ("all_proxy", socksProxy),
                ("no_proxy", noProxy),
            ]
        }
    }

    /// Also set uppercase variants (HTTP_PROXY, HTTPS_PROXY, etc.)
    public var allEntries: [(envName: String, value: String)] {
        entries.flatMap { entry in
            [entry, (entry.envName.uppercased(), entry.value)]
        }
    }
}

// MARK: - Agent Hook Model

/// Represents the enable/disable state of agent hooks.
public struct AgentHookModel: Equatable {
    public var claudeEnabled: Bool
    public var codexEnabled: Bool
    public var piEnabled: Bool
    public var droidEnabled: Bool

    public init(claudeEnabled: Bool = false, codexEnabled: Bool = false, piEnabled: Bool = false, droidEnabled: Bool = false) {
        self.claudeEnabled = claudeEnabled
        self.codexEnabled = codexEnabled
        self.piEnabled = piEnabled
        self.droidEnabled = droidEnabled
    }
}

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case theme = "Theme"
    case fonts = "Fonts"
    case cursor = "Cursor"
    case keyboard = "Keyboard"
    case mouse = "Mouse"
    case window = "Window"
    case tools = "Tools"
    case network = "Network"
    case agents = "Agent Hooks"

    var id: String { rawValue }

    var localizedName: String {
        .localized(String.LocalizationValue(stringLiteral: rawValue))
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .theme: return "paintpalette"
        case .fonts: return "textformat"
        case .cursor: return "character.cursor.ibeam"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .window: return "macwindow"
        case .tools: return "hammer"
        case .network: return "network"
        case .agents: return "cpu"
        }
    }
}

// MARK: - Main Settings View

public struct GhosttySettingsView: View {
    @Binding var model: GhosttySettingsModel
    var availableThemes: [String]
    var ghosttyDefaults: [String]
    var onChanged: () -> Void
    var onOpenConfigFile: () -> Void
    @Binding var agentHooks: AgentHookModel
    var onAgentHookChanged: ((AgentHookModel) -> Void)?
    @Binding var proxySettings: ProxySettingsModel
    var onProxyApply: ((ProxySettingsModel) -> Void)?
    var onSystemProxyDetect: (() -> ProxySettingsModel)?
    @Binding var toolSettings: ToolSettings
    var onToolSettingsChanged: ((ToolSettings) -> Void)?

    // Key bindings
    var keyBindings: [KeyBinding]
    var keyBindingDefaults: [KeyBinding]
    var onKeyBindingValidate: ((KeyBinding) -> ConflictResult)?
    var onKeyBindingUpdate: ((KeyBinding) -> Void)?
    var onKeyBindingReset: ((String) -> Void)?
    var onKeyBindingResetAll: (() -> Void)?

    @State private var selectedCategory: SettingsCategory = .general

    public init(
        model: Binding<GhosttySettingsModel>,
        availableThemes: [String],
        ghosttyDefaults: [String] = [],
        onChanged: @escaping () -> Void,
        onOpenConfigFile: @escaping () -> Void,
        agentHooks: Binding<AgentHookModel> = .constant(AgentHookModel()),
        onAgentHookChanged: ((AgentHookModel) -> Void)? = nil,
        proxySettings: Binding<ProxySettingsModel> = .constant(ProxySettingsModel()),
        onProxyApply: ((ProxySettingsModel) -> Void)? = nil,
        onSystemProxyDetect: (() -> ProxySettingsModel)? = nil,
        toolSettings: Binding<ToolSettings> = .constant(ToolSettings()),
        onToolSettingsChanged: ((ToolSettings) -> Void)? = nil,
        keyBindings: [KeyBinding] = [],
        keyBindingDefaults: [KeyBinding] = [],
        onKeyBindingValidate: ((KeyBinding) -> ConflictResult)? = nil,
        onKeyBindingUpdate: ((KeyBinding) -> Void)? = nil,
        onKeyBindingReset: ((String) -> Void)? = nil,
        onKeyBindingResetAll: (() -> Void)? = nil
    ) {
        self._model = model
        self.availableThemes = availableThemes
        self.ghosttyDefaults = ghosttyDefaults
        self.onChanged = onChanged
        self.onOpenConfigFile = onOpenConfigFile
        self._agentHooks = agentHooks
        self.onAgentHookChanged = onAgentHookChanged
        self._proxySettings = proxySettings
        self.onProxyApply = onProxyApply
        self.onSystemProxyDetect = onSystemProxyDetect
        self._toolSettings = toolSettings
        self.onToolSettingsChanged = onToolSettingsChanged
        self.keyBindings = keyBindings
        self.keyBindingDefaults = keyBindingDefaults
        self.onKeyBindingValidate = onKeyBindingValidate
        self.onKeyBindingUpdate = onKeyBindingUpdate
        self.onKeyBindingReset = onKeyBindingReset
        self.onKeyBindingResetAll = onKeyBindingResetAll
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 740, idealWidth: 780, minHeight: 540, idealHeight: 600)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsCategory.allCases) { category in
                    sidebarRow(category)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            Spacer()

            Divider()
                .padding(.horizontal, 12)

            Button(action: onOpenConfigFile) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                    Text("Open Ghostty Config in Editor")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .frame(width: 180)
    }

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(category.localizedName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(selectedCategory.localizedName)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedCategory {
                    case .general: GeneralSettingsContent()
                    case .theme: ThemeSettingsContent(model: $model, availableThemes: availableThemes, onChanged: onChanged)
                    case .fonts: FontSettingsContent(model: $model, onChanged: onChanged)
                    case .cursor: CursorSettingsContent(model: $model, onChanged: onChanged)
                    case .keyboard: KeyboardSettingsContent(
                        model: $model,
                        onChanged: onChanged,
                        ghosttyDefaults: ghosttyDefaults,
                        keyBindings: keyBindings,
                        keyBindingDefaults: keyBindingDefaults,
                        onKeyBindingValidate: onKeyBindingValidate,
                        onKeyBindingUpdate: onKeyBindingUpdate,
                        onKeyBindingReset: onKeyBindingReset,
                        onKeyBindingResetAll: onKeyBindingResetAll
                    )
                    case .mouse: MouseSettingsContent(model: $model, onChanged: onChanged)
                    case .window: WindowSettingsContent(model: $model, onChanged: onChanged)
                    case .tools: ToolSettingsContent(
                        model: $toolSettings,
                        onApply: { onToolSettingsChanged?(toolSettings) }
                    )
                    case .network: NetworkSettingsContent(
                        model: $proxySettings,
                        onApply: { onProxyApply?(proxySettings) },
                        onSystemProxyDetect: onSystemProxyDetect
                    )
                    case .agents: AgentHookSettingsContent(model: $agentHooks, onChanged: { onAgentHookChanged?(agentHooks) })
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Setting Row Components

/// A single setting row with title, optional description, and a control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: description != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
    }
}

/// A card container for grouping related settings.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct CardDivider: View {
    var body: some View {
        Divider().padding(.vertical, 12)
    }
}

// MARK: - Terminal Preview

/// Simulated terminal preview showing font, theme colors, and cursor.
private struct TerminalPreview: View {
    let fontFamily: String
    let fontSize: Int
    let cursorStyle: String
    let opacity: Double

    private var previewFont: Font {
        let name = fontFamily.isEmpty ? "SF Mono" : fontFamily
        return .custom(name, size: CGFloat(fontSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Circle().fill(.red.opacity(0.8)).frame(width: 10, height: 10)
                Circle().fill(.yellow.opacity(0.8)).frame(width: 10, height: 10)
                Circle().fill(.green.opacity(0.8)).frame(width: 10, height: 10)
                Spacer()
                Text("Terminal Preview")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))

            // Terminal content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("user").foregroundStyle(.green) +
                    Text("@").foregroundStyle(.secondary) +
                    Text("mori").foregroundStyle(.cyan)
                    Text(" ~ $ ").foregroundStyle(.secondary)
                    Text("ls -la").foregroundStyle(.primary)
                }

                HStack(spacing: 0) {
                    Text("drwxr-xr-x  ").foregroundStyle(.secondary)
                    Text("src/").foregroundStyle(.blue)
                }

                HStack(spacing: 0) {
                    Text("-rw-r--r--  ").foregroundStyle(.secondary)
                    Text("README.md").foregroundStyle(.primary)
                }

                HStack(spacing: 0) {
                    Text("-rw-r--r--  ").foregroundStyle(.secondary)
                    Text("Package.swift").foregroundStyle(.yellow)
                }

                HStack(spacing: 0) {
                    Text("user").foregroundStyle(.green) +
                    Text("@").foregroundStyle(.secondary) +
                    Text("mori").foregroundStyle(.cyan)
                    Text(" ~ $ ").foregroundStyle(.secondary)
                    cursorView
                }
            }
            .font(previewFont)
            .padding(10)
        }
        .background(Color.black.opacity(opacity))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cursorView: some View {
        switch cursorStyle {
        case "bar":
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 2, height: CGFloat(fontSize))
        case "underline":
            VStack(spacing: 0) {
                Color.clear.frame(height: CGFloat(fontSize) - 2)
                Rectangle().fill(Color.white.opacity(0.8)).frame(width: CGFloat(fontSize) * 0.6, height: 2)
            }
            .frame(height: CGFloat(fontSize))
        default: // block
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: CGFloat(fontSize) * 0.6, height: CGFloat(fontSize))
        }
    }
}

// MARK: - General Settings

private struct GeneralSettingsContent: View {
    private static let supportedLanguages: [(name: String, locale: String)] = [
        ("English", "en"),
        ("简体中文", "zh-Hans"),
    ]

    @State private var selectedLocale: String = {
        let lang = String.moriLanguage
        return lang.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
    }()

    var body: some View {
        SettingsCard {
            SettingRow(
                title: .localized("Language"),
                description: .localized("Choose the display language for Mori.")
            ) {
                Picker("", selection: $selectedLocale) {
                    ForEach(Self.supportedLanguages, id: \.locale) { language in
                        Text(language.name).tag(language.locale)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: selectedLocale) { _, newValue in
                    String.setMoriLanguage(newValue)
                }
            }

            CardDivider()

            Text(String.localized("Restart Mori to apply language change."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Theme Settings

private struct ThemeSettingsContent: View {
    private enum BackgroundBlurPreset: String, CaseIterable, Identifiable {
        case disabled
        case standard
        case custom
        case macosGlassRegular
        case macosGlassClear

        var id: String { rawValue }
    }

    @Binding var model: GhosttySettingsModel
    let availableThemes: [String]
    let onChanged: () -> Void

    @State private var themeSearch = ""

    private var blurPreset: Binding<BackgroundBlurPreset> {
        Binding(
            get: {
                switch model.backgroundBlur {
                case .disabled: .disabled
                case .standard: .standard
                case .radius: .custom
                case .macosGlassRegular: .macosGlassRegular
                case .macosGlassClear: .macosGlassClear
                }
            },
            set: { preset in
                switch preset {
                case .disabled:
                    model.backgroundBlur = .disabled
                case .standard:
                    model.backgroundBlur = .standard
                case .custom:
                    model.backgroundBlur = .radius(model.backgroundBlur.radiusValue)
                case .macosGlassRegular:
                    model.backgroundBlur = .macosGlassRegular
                case .macosGlassClear:
                    model.backgroundBlur = .macosGlassClear
                }
                onChanged()
            }
        )
    }

    private var blurRadius: Binding<Double> {
        Binding(
            get: { Double(model.backgroundBlur.radiusValue) },
            set: { newValue in
                model.backgroundBlur = .radius(Int(newValue.rounded()))
                onChanged()
            }
        )
    }

    var body: some View {
        // Preview
        TerminalPreview(
            fontFamily: model.fontFamily,
            fontSize: model.fontSize,
            cursorStyle: model.cursorStyle,
            opacity: model.backgroundOpacity
        )

        // Theme settings card
        SettingsCard {
            SettingRow(
                title: .localized("Color theme"),
                description: .localized("Select a color scheme for the terminal.")
            ) {
                Text(model.theme.isEmpty ? .localized("Default") : model.theme)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .trailing)
            }

            CardDivider()

            // Theme search and list
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Search themes…", text: $themeSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !themeSearch.isEmpty {
                    Button { themeSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredThemes, id: \.self) { name in
                        themeListRow(name)
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            CardDivider()

            SettingRow(
                title: .localized("Background opacity"),
                description: .localized("Translucent background behind the terminal content.")
            ) {
                HStack(spacing: 8) {
                    Text(String(format: "%.2f", model.backgroundOpacity))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    Slider(value: $model.backgroundOpacity, in: 0.1...1.0, step: 0.05)
                        .frame(width: 140)
                        .onChange(of: model.backgroundOpacity) { _, _ in onChanged() }
                }
            }

            CardDivider()

            SettingRow(
                title: .localized("Apply opacity to colored cells"),
                description: .localized("Let tmux and terminal apps keep translucent backgrounds when they draw colored cells instead of using the default terminal background.")
            ) {
                Toggle("", isOn: $model.backgroundOpacityCells)
                    .labelsHidden()
                    .onChange(of: model.backgroundOpacityCells) { _, _ in onChanged() }
            }

            CardDivider()

            SettingRow(
                title: .localized("Background blur"),
                description: .localized("Inherit Ghostty window blur and glass styling for translucent terminal backgrounds.")
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    Picker("", selection: blurPreset) {
                        Text(String.localized("Off")).tag(BackgroundBlurPreset.disabled)
                        Text(String.localized("Standard Blur")).tag(BackgroundBlurPreset.standard)
                        Text(String.localized("Custom Blur Radius")).tag(BackgroundBlurPreset.custom)
                        if #available(macOS 26.0, *) {
                            Text(String.localized("Glass Regular")).tag(BackgroundBlurPreset.macosGlassRegular)
                            Text(String.localized("Glass Clear")).tag(BackgroundBlurPreset.macosGlassClear)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)

                    if case .radius = model.backgroundBlur {
                        HStack(spacing: 8) {
                            Text("\(model.backgroundBlur.radiusValue)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            Slider(value: blurRadius, in: 1...60, step: 1)
                                .frame(width: 140)
                        }
                    }

                    if model.backgroundOpacity >= 1, model.backgroundBlur != .disabled {
                        Text(String.localized("Background blur is only visible when background opacity is below 1.0."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var filteredThemes: [String] {
        guard !themeSearch.isEmpty else { return availableThemes }
        let query = themeSearch.lowercased()
        return availableThemes.filter { $0.lowercased().contains(query) }
    }

    @ViewBuilder
    private func themeListRow(_ name: String) -> some View {
        let isSelected = model.theme.lowercased() == name.lowercased()
        HStack {
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.theme = name
            onChanged()
        }
    }
}

// MARK: - Font Settings

private struct FontSettingsContent: View {
    @Binding var model: GhosttySettingsModel
    let onChanged: () -> Void

    @State private var fontSearch = ""

    var body: some View {
        TerminalPreview(
            fontFamily: model.fontFamily,
            fontSize: model.fontSize,
            cursorStyle: model.cursorStyle,
            opacity: model.backgroundOpacity
        )

        SettingsCard {
            SettingRow(
                title: .localized("Font family"),
                description: .localized("The font to use for terminal text. Leave empty for the default.")
            ) {
                TextField("SF Mono", text: $model.fontFamily)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .font(.system(size: 12))
                    .onChange(of: model.fontFamily) { _, _ in onChanged() }
            }

            CardDivider()

            SettingRow(
                title: .localized("Font size"),
                description: .localized("Size in points for terminal text.")
            ) {
                HStack(spacing: 8) {
                    Text("\(model.fontSize) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                    Stepper("", value: $model.fontSize, in: 6...48)
                        .labelsHidden()
                        .onChange(of: model.fontSize) { _, _ in onChanged() }
                }
            }
        }

        // Monospace font browser
        SettingsCard {
            Text("Available Monospace Fonts")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Filter fonts…", text: $fontSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFonts, id: \.self) { family in
                        fontRow(family)
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func fontRow(_ family: String) -> some View {
        let isSelected = model.fontFamily.lowercased() == family.lowercased()
        HStack {
            Text(family)
                .font(.custom(family, size: 13))
                .lineLimit(1)
            Spacer()
            Text("Aa 0O Il 1l")
                .font(.custom(family, size: 11))
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.fontFamily = family
            onChanged()
        }
    }

    private var monospacedFonts: [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13)
            else { return false }
            return font.isFixedPitch || Self.hasUniformGlyphAdvance(font)
        }.sorted()
    }

    private static func hasUniformGlyphAdvance(_ font: NSFont) -> Bool {
        let ctFont = font as CTFont
        let sampleCharacters: [UniChar] = Array(" .0OIl1AaMWmw".utf16)
        var characters = sampleCharacters
        var glyphs = Array(repeating: CGGlyph(), count: sampleCharacters.count)

        guard CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, sampleCharacters.count) else {
            return false
        }

        var advances = Array(repeating: CGSize.zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)

        guard let expectedWidth = advances.first?.width else { return false }
        return advances.allSatisfy { abs($0.width - expectedWidth) < 0.01 }
    }

    private var filteredFonts: [String] {
        let all = monospacedFonts
        guard !fontSearch.isEmpty else { return all }
        let query = fontSearch.lowercased()
        return all.filter { $0.lowercased().contains(query) }
    }
}

// MARK: - Cursor Settings

private struct CursorSettingsContent: View {
    @Binding var model: GhosttySettingsModel
    let onChanged: () -> Void

    var body: some View {
        TerminalPreview(
            fontFamily: model.fontFamily,
            fontSize: model.fontSize,
            cursorStyle: model.cursorStyle,
            opacity: model.backgroundOpacity
        )

        SettingsCard {
            SettingRow(
                title: .localized("Cursor style"),
                description: .localized("The shape of the cursor in the terminal.")
            ) {
                Picker("", selection: $model.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: model.cursorStyle) { _, _ in onChanged() }
            }

            CardDivider()

            SettingRow(
                title: .localized("Cursor blink"),
                description: .localized("Whether the cursor blinks when idle.")
            ) {
                Toggle("", isOn: $model.cursorBlink)
                    .labelsHidden()
                    .onChange(of: model.cursorBlink) { _, _ in onChanged() }
            }
        }
    }
}

// MARK: - Keyboard Settings

/// A single keybind entry for display.
private struct KeybindEntry: Identifiable {
    let id: String
    let keys: String
    let action: String
    let source: KeybindSource

    enum KeybindSource {
        case mori       // Mori app shortcuts (not editable)
        case ghostty    // Ghostty defaults (not editable here)
        case user       // User overrides in ghostty config (editable)
    }
}

private struct KeyboardSettingsContent: View {
    @Binding var model: GhosttySettingsModel
    let onChanged: () -> Void
    let ghosttyDefaults: [String]

    // Key bindings data + callbacks
    var keyBindings: [KeyBinding]
    var keyBindingDefaults: [KeyBinding]
    var onKeyBindingValidate: ((KeyBinding) -> ConflictResult)?
    var onKeyBindingUpdate: ((KeyBinding) -> Void)?
    var onKeyBindingReset: ((String) -> Void)?
    var onKeyBindingResetAll: (() -> Void)?

    @State private var keybindFilter = ""
    @State private var newKeybind = ""

    init(
        model: Binding<GhosttySettingsModel>,
        onChanged: @escaping () -> Void,
        ghosttyDefaults: [String] = [],
        keyBindings: [KeyBinding] = [],
        keyBindingDefaults: [KeyBinding] = [],
        onKeyBindingValidate: ((KeyBinding) -> ConflictResult)? = nil,
        onKeyBindingUpdate: ((KeyBinding) -> Void)? = nil,
        onKeyBindingReset: ((String) -> Void)? = nil,
        onKeyBindingResetAll: (() -> Void)? = nil
    ) {
        self._model = model
        self.onChanged = onChanged
        self.ghosttyDefaults = ghosttyDefaults
        self.keyBindings = keyBindings
        self.keyBindingDefaults = keyBindingDefaults
        self.onKeyBindingValidate = onKeyBindingValidate
        self.onKeyBindingUpdate = onKeyBindingUpdate
        self.onKeyBindingReset = onKeyBindingReset
        self.onKeyBindingResetAll = onKeyBindingResetAll
    }

    var body: some View {
        SettingsCard {
            SettingRow(
                title: .localized("Option as Alt"),
                description: .localized("Treat the macOS Option key as Alt for terminal escape sequences.")
            ) {
                Picker("", selection: $model.macosOptionAsAlt) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: model.macosOptionAsAlt) { _, _ in onChanged() }
            }
        }

        // Mori key bindings (editable)
        if !keyBindings.isEmpty {
            SettingsCard {
                HStack {
                    Text(String.localized("Mori App"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }

                KeyBindingsSettingsView(
                    bindings: keyBindings,
                    defaults: keyBindingDefaults,
                    onValidate: { onKeyBindingValidate?($0) ?? .none },
                    onUpdate: { onKeyBindingUpdate?($0) },
                    onReset: { onKeyBindingReset?($0) },
                    onResetAll: { onKeyBindingResetAll?() }
                )
            }
        }

        // Ghostty keybindings (terminal-level, read-only display)
        SettingsCard {
            HStack {
                Text(String.localized("Ghostty Terminal Keybindings"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            Text(String.localized("Terminal keybindings are configured via ~/.config/ghostty/config"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // Search filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Filter keybindings…", text: $keybindFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !keybindFilter.isEmpty {
                    Button { keybindFilter = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    // User overrides first
                    if !filteredUserBinds.isEmpty {
                        keybindSectionHeader(.localized("User Overrides"), count: filteredUserBinds.count)
                        ForEach(Array(filteredUserBinds.enumerated()), id: \.offset) { index, entry in
                            userKeybindRow(entry, index: index)
                        }
                    }

                    // Ghostty defaults
                    if !filteredGhosttyBinds.isEmpty {
                        keybindSectionHeader(.localized("Ghostty Defaults"), count: filteredGhosttyBinds.count)
                        ForEach(filteredGhosttyBinds) { entry in
                            keybindRow(entry)
                        }
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            CardDivider()

            // Add new keybind
            HStack(spacing: 8) {
                TextField("e.g. super+k=clear_screen", text: $newKeybind)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { addKeybind() }

                Button(action: addKeybind) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newKeybind.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )

            Text("Format: key_combo=action (e.g. super+shift+p=toggle_command_palette)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func addKeybind() {
        let trimmed = newKeybind.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.keybinds.append(trimmed)
        newKeybind = ""
        onChanged()
    }

    // MARK: - Keybind Rows

    private func keybindSectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func keybindRow(_ entry: KeybindEntry) -> some View {
        HStack {
            Text(entry.keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 140, alignment: .leading)

            Text(entry.action)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func userKeybindRow(_ entry: KeybindEntry, index: Int) -> some View {
        HStack {
            Text(entry.keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 140, alignment: .leading)

            Text(entry.action)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                model.keybinds.remove(at: index)
                onChanged()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.05))
    }

    // MARK: - Data

    private var ghosttyEntries: [KeybindEntry] {
        ghosttyDefaults.enumerated().compactMap { index, raw in
            guard let eqIndex = raw.firstIndex(of: "=") else { return nil }
            let keys = String(raw[raw.startIndex..<eqIndex])
            let action = String(raw[raw.index(after: eqIndex)...])
            return KeybindEntry(id: "g.\(index)", keys: keys, action: action, source: .ghostty)
        }
    }

    private var userEntries: [KeybindEntry] {
        model.keybinds.enumerated().compactMap { index, raw in
            guard let eqIndex = raw.firstIndex(of: "=") else { return nil }
            let keys = String(raw[raw.startIndex..<eqIndex])
            let action = String(raw[raw.index(after: eqIndex)...])
            return KeybindEntry(id: "u.\(index)", keys: keys, action: action, source: .user)
        }
    }

    private var filteredGhosttyBinds: [KeybindEntry] {
        filterEntries(ghosttyEntries)
    }

    private var filteredUserBinds: [KeybindEntry] {
        filterEntries(userEntries)
    }

    private func filterEntries(_ entries: [KeybindEntry]) -> [KeybindEntry] {
        guard !keybindFilter.isEmpty else { return entries }
        let query = keybindFilter.lowercased()
        return entries.filter {
            $0.keys.lowercased().contains(query) || $0.action.lowercased().contains(query)
        }
    }
}

// MARK: - Mouse Settings

private struct MouseSettingsContent: View {
    @Binding var model: GhosttySettingsModel
    let onChanged: () -> Void

    var body: some View {
        SettingsCard {
            SettingRow(
                title: .localized("Hide while typing"),
                description: .localized("Automatically hide the mouse cursor when typing in the terminal.")
            ) {
                Toggle("", isOn: $model.mouseHideWhileTyping)
                    .labelsHidden()
                    .onChange(of: model.mouseHideWhileTyping) { _, _ in onChanged() }
            }

            CardDivider()

            SettingRow(
                title: .localized("Scroll multiplier"),
                description: .localized("Multiplier for mouse scroll speed.")
            ) {
                HStack(spacing: 8) {
                    Text("\(model.mouseScrollMultiplier)x")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Stepper("", value: $model.mouseScrollMultiplier, in: 1...10)
                        .labelsHidden()
                        .onChange(of: model.mouseScrollMultiplier) { _, _ in onChanged() }
                }
            }

            CardDivider()

            SettingRow(
                title: .localized("Copy on select"),
                description: .localized("Automatically copy selected text to the clipboard.")
            ) {
                Picker("", selection: $model.copyOnSelect) {
                    Text("Off").tag("false")
                    Text("On").tag("true")
                    Text("Clipboard").tag("clipboard")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: model.copyOnSelect) { _, _ in onChanged() }
            }
        }
    }
}

// MARK: - Window Settings

private struct WindowSettingsContent: View {
    @Binding var model: GhosttySettingsModel
    let onChanged: () -> Void

    var body: some View {
        SettingsCard {
            SettingRow(
                title: .localized("Balance window padding"),
                description: .localized("Distribute extra padding evenly around the terminal content to center it within the window.")
            ) {
                Toggle("", isOn: $model.windowPaddingBalance)
                    .labelsHidden()
                    .onChange(of: model.windowPaddingBalance) { _, _ in onChanged() }
            }
        }
    }
}

// MARK: - Tool Settings

private struct ToolSettingsContent: View {
    private static let tools: [(command: String, description: String)] = [
        ("tmux", .localized("Required for local Mori workspaces. Supports custom installs such as ~/homebrew/bin/tmux.")),
        ("lazygit", .localized("Optional Git companion tool path.")),
        ("yazi", .localized("Optional file manager companion tool path.")),
    ]

    @Binding var model: ToolSettings
    let onApply: () -> Void

    @State private var hasUnappliedChanges = false

    var body: some View {
        Text(String.localized("Configure explicit paths for tmux, Lazygit, and Yazi, and choose whether Mori should apply its tmux onboarding defaults. Leave a path field empty to let Mori auto-detect from common install locations and your shell PATH."))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        SettingsCard {
            SettingRow(
                title: .localized("Apply Mori tmux defaults"),
                description: .localized("Enable mouse support and hide the tmux status bar for Mori-managed sessions. Turn this off to keep your own mouse and status-bar behavior from tmux.conf instead.")
            ) {
                Toggle("", isOn: $model.applyMoriTmuxDefaults)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: model.applyMoriTmuxDefaults) { _, _ in
                        hasUnappliedChanges = true
                    }
            }
        }

        SettingsCard {
            ForEach(Array(Self.tools.enumerated()), id: \.element.command) { index, tool in
                toolRow(command: tool.command, description: tool.description)

                if index < Self.tools.count - 1 {
                    CardDivider()
                }
            }
        }

        SettingsCard {
            HStack {
                Button(String.localized("Apply")) {
                    onApply()
                    hasUnappliedChanges = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnappliedChanges)

                if hasUnappliedChanges {
                    Text(String.localized("Unsaved changes"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(String.localized("Tmux preset changes apply immediately to Mori-managed sessions. Tool path changes apply to new launches, while existing tmux clients or shells may still use earlier paths until reopened."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func toolRow(command: String, description: String) -> some View {
        let value = toolBinding(for: command)
        let resolvedPath = model.displayPath(for: command)
        let hasOverride = !(model.trimmedRawPath(for: command) ?? "").isEmpty

        return SettingRow(title: command, description: description) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(String.localized("Resolved automatically"), text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: value.wrappedValue) { _, _ in
                        hasUnappliedChanges = true
                    }

                if !resolvedPath.isEmpty {
                    Text(
                        hasOverride
                            ? String(format: .localized("Using override: %@"), resolvedPath)
                            : String(format: .localized("Auto-detected: %@"), resolvedPath)
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 280, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func toolBinding(for command: String) -> Binding<String> {
        Binding(
            get: {
                model.rawPath(for: command) ?? ""
            },
            set: { newValue in
                model.setRawPath(newValue, for: command)
            }
        )
    }
}

// MARK: - Network Settings

private struct NetworkSettingsContent: View {
    @Binding var model: ProxySettingsModel
    let onApply: () -> Void
    var onSystemProxyDetect: (() -> ProxySettingsModel)?

    @State private var hasUnappliedChanges = false

    var body: some View {
        Text(String.localized("Configure proxy environment variables for all terminal sessions. Both lowercase and uppercase variants (e.g. http_proxy and HTTP_PROXY) are set automatically."))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // Mode selector
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String.localized("Proxy Mode"))
                    .font(.system(size: 13, weight: .semibold))

                modeRow(.system,
                        title: .localized("System proxy"),
                        description: .localized("Read proxy settings from macOS system configuration."))
                modeRow(.manual,
                        title: .localized("Manual configuration"),
                        description: .localized("Specify proxy URLs manually."))
                modeRow(.none,
                        title: .localized("No proxy"),
                        description: .localized("Clear all proxy environment variables."))
            }
        }

        // Proxy fields (shown for system and manual modes)
        if model.mode != .none {
            SettingsCard {
                SettingRow(
                    title: "HTTP Proxy",
                    description: .localized("HTTP proxy URL (e.g. http://127.0.0.1:7890)")
                ) {
                    proxyField($model.httpProxy, disabled: model.mode == .system)
                }

                CardDivider()

                SettingRow(
                    title: "HTTPS Proxy",
                    description: .localized("HTTPS proxy URL (e.g. http://127.0.0.1:7890)")
                ) {
                    if model.mode == .manual {
                        VStack(alignment: .trailing, spacing: 4) {
                            proxyField(
                                model.sameForHTTPS ? .constant(model.httpProxy) : $model.httpsProxy,
                                disabled: model.sameForHTTPS
                            )
                            Toggle(String.localized("Same as HTTP"), isOn: $model.sameForHTTPS)
                                .font(.system(size: 11))
                                .toggleStyle(.checkbox)
                                .onChange(of: model.sameForHTTPS) { _, _ in hasUnappliedChanges = true }
                        }
                    } else {
                        proxyField($model.httpsProxy, disabled: true)
                    }
                }

                CardDivider()

                SettingRow(
                    title: "SOCKS Proxy",
                    description: .localized("SOCKS proxy URL (e.g. socks5://127.0.0.1:7890)")
                ) {
                    proxyField($model.socksProxy, disabled: model.mode == .system)
                }

                CardDivider()

                SettingRow(
                    title: .localized("Bypass List"),
                    description: .localized("Comma-separated hosts to bypass proxy (e.g. localhost,127.0.0.1)")
                ) {
                    proxyField($model.noProxy, disabled: model.mode == .system)
                }
            }
        }

        // Apply bar
        SettingsCard {
            HStack {
                Button(String.localized("Apply")) {
                    onApply()
                    hasUnappliedChanges = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnappliedChanges)

                if hasUnappliedChanges {
                    Text(String.localized("Unsaved changes"))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(String.localized("Proxy changes only affect new tabs and panes. Existing shells keep their current environment."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Components

    private func modeRow(_ mode: ProxyMode, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: model.mode == mode ? "circle.inset.filled" : "circle")
                .foregroundStyle(model.mode == mode ? Color.accentColor : .secondary)
                .font(.system(size: 14))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: model.mode == mode ? .semibold : .regular))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let previousMode = model.mode
            model.mode = mode
            if mode == .system, let detect = onSystemProxyDetect {
                let system = detect()
                model.httpProxy = system.httpProxy
                model.httpsProxy = system.httpsProxy
                model.socksProxy = system.socksProxy
                model.noProxy = system.noProxy
                model.sameForHTTPS = false
            } else if mode == .none && previousMode != .none {
                model.httpProxy = ""
                model.httpsProxy = ""
                model.socksProxy = ""
                model.noProxy = ""
            }
            hasUnappliedChanges = true
        }
    }

    private func proxyField(_ value: Binding<String>, disabled: Bool = false) -> some View {
        TextField("", text: value)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
            .font(.system(size: 12, design: .monospaced))
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1.0)
            .onChange(of: value.wrappedValue) { _, _ in
                if !disabled { hasUnappliedChanges = true }
            }
    }
}

// MARK: - Agent Hook Settings

private struct AgentHookSettingsContent: View {
    @Binding var model: AgentHookModel
    let onChanged: () -> Void

    var body: some View {
        Text("Connect coding agents to Mori so their status appears in tab names and triggers notifications. Each hook writes a small script to ~/.config/mori/ and registers it with the agent.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        agentCard(
            name: .localized("Claude Code"),
            icon: "terminal",
            description: .localized("Adds hooks to ~/.claude/settings.json for prompt submit, tool use, stop, and notification events."),
            isEnabled: $model.claudeEnabled
        )

        agentCard(
            name: .localized("Codex CLI"),
            icon: "chevron.left.forwardslash.chevron.right",
            description: .localized("Adds a notify entry to ~/.codex/config.toml for agent turn completion events."),
            isEnabled: $model.codexEnabled
        )

        agentCard(
            name: .localized("Pi"),
            icon: "sparkle",
            description: .localized("Registers an extension in Pi's settings.json for agent start, end, and tool execution events."),
            isEnabled: $model.piEnabled
        )

        agentCard(
            name: .localized("Droid"),
            icon: "cpu",
            description: .localized("Adds hooks to ~/.factory/settings.json for prompt submit, tool use, stop, and notification events."),
            isEnabled: $model.droidEnabled
        )
    }

    private func agentCard(
        name: String,
        icon: String,
        description: String,
        isEnabled: Binding<Bool>
    ) -> some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: isEnabled)
                            .labelsHidden()
                            .onChange(of: isEnabled.wrappedValue) { _, _ in onChanged() }
                    }
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
