import AppKit
import MoriCore
import MoriTerminal

@MainActor
enum CompanionTool: String, CaseIterable {
    case yazi
    case lazygit

    var command: String { rawValue }

    var title: String {
        switch self {
        case .yazi: .localized("Files")
        case .lazygit: .localized("Git")
        }
    }

    var symbolName: String {
        switch self {
        case .yazi: "folder"
        case .lazygit: "arrow.triangle.branch"
        }
    }

    /// Tooltip including the keyboard shortcut that toggles this tool.
    var tabTooltip: String {
        switch self {
        case .yazi: .localized("Files (⌘E)")
        case .lazygit: .localized("Git (⌘G)")
        }
    }
}

enum CompanionToolPanePresentation {
    case closed
    case docked
}

struct CompanionToolPaneState {
    var activeTool: CompanionTool?
    var presentation: CompanionToolPanePresentation
    var width: CGFloat

    static let defaultWidth: CGFloat = 420

    init(
        activeTool: CompanionTool? = nil,
        presentation: CompanionToolPanePresentation = .closed,
        width: CGFloat = Self.defaultWidth
    ) {
        self.activeTool = activeTool
        self.presentation = presentation
        self.width = width
    }

    var isVisible: Bool {
        presentation != .closed && activeTool != nil
    }
}

struct CompanionToolLaunchContext {
    let workspaceID: String
    let workingDirectory: String
    let location: WorkspaceLocation
}

@MainActor
final class CompanionToolPaneController: NSViewController, ThemedSurface {
    var themedWindow: NSWindow? { nil }

    private let tabBar: CompanionTabBarView
    private let terminalController: TerminalAreaViewController

    private(set) var activeTool: CompanionTool?

    /// Invoked when the embedded tool's process exits (e.g., user presses `q` in lazygit).
    /// The owner should close the companion pane in response.
    var onToolExited: (() -> Void)?

    /// Invoked when a tab is clicked: the owner opens the pane on `tool`, switches to
    /// it, or focuses it — a *select* (never a close). Distinct from ⌘E/⌘G toggling.
    var onSelectTool: ((CompanionTool) -> Void)?

    init(terminalHost: TerminalHost? = nil) {
        self.terminalController = TerminalAreaViewController(terminalHost: terminalHost)
        self.tabBar = CompanionTabBarView()
        super.init(nibName: nil, bundle: nil)
        terminalController.onSurfaceExited = { [weak self] in
            guard let self else { return }
            self.activeTool = nil
            self.onToolExited?()
        }
        tabBar.onSelect = { [weak self] tool in self?.onSelectTool?(tool) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false

        tabBar.translatesAutoresizingMaskIntoConstraints = false

        addChild(terminalController)
        let terminalView = terminalController.view
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(tabBar)
        root.addSubview(terminalView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TitleBarDragView.height),

            terminalView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root
    }

    func show(tool: CompanionTool, context: CompanionToolLaunchContext, focus: Bool = true) {
        activeTool = tool
        tabBar.setActiveTool(tool)
        let identity = "tool|\(tool.rawValue)|\(context.location.endpointKey)|\(context.workspaceID)"
        terminalController.attachToCommand(
            identity: identity,
            command: tool.command,
            workingDirectory: context.workingDirectory,
            location: context.location,
            focus: focus
        )
        if focus {
            terminalController.focusCurrentSurface()
        }
    }

    /// Move keyboard focus into the embedded tool without re-attaching it.
    func focus() {
        terminalController.focusCurrentSurface()
    }

    func isFocused(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        tabBar.applyTheme(themeInfo)
        terminalController.applyTheme(themeInfo)
    }
}

/// The companion column's 38pt header: Files / Git tabs leading, a drag-through gap,
/// over a hairline matching `HeaderBarView` so the two column headers read as one
/// band. Empty area still drags the window. The pane deliberately carries no close
/// button — dismissal lives in the center header's toggle and ⌘E/⌘G.
@MainActor
final class CompanionTabBarView: TitleBarDragView {
    private static let leadingInset: CGFloat = 10
    private static let tabSpacing: CGFloat = 4

    private let filesTab = CompanionTabButton(tool: .yazi)
    private let gitTab = CompanionTabButton(tool: .lazygit)
    private let hairline = NSView()

    var onSelect: ((CompanionTool) -> Void)?

    init() {
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true

        for tab in [filesTab, gitTab] {
            tab.translatesAutoresizingMaskIntoConstraints = false
            tab.target = self
            tab.action = #selector(tabClicked(_:))
            tab.toolTip = tab.tool.tabTooltip
        }

        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true

        addSubview(filesTab)
        addSubview(gitTab)
        addSubview(hairline)

        NSLayoutConstraint.activate([
            filesTab.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            filesTab.centerYAnchor.constraint(equalTo: centerYAnchor),

            gitTab.leadingAnchor.constraint(equalTo: filesTab.trailingAnchor, constant: Self.tabSpacing),
            gitTab.centerYAnchor.constraint(equalTo: centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    func setActiveTool(_ tool: CompanionTool?) {
        filesTab.isActive = tool == .yazi
        gitTab.isActive = tool == .lazygit
    }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        // Deterministic tint (not labelColor) so split light/dark themes stay correct.
        let tint: NSColor = themeInfo.isDark ? .white : .black
        hairline.layer?.backgroundColor = tint.withAlphaComponent(0.06).cgColor
        filesTab.applyTheme(isDark: themeInfo.isDark)
        gitTab.applyTheme(isDark: themeInfo.isDark)
    }

    @objc private func tabClicked(_ sender: CompanionTabButton) {
        onSelect?(sender.tool)
    }
}

/// A single icon+label tab. Active = labelColor ~9% fill (rounded 6); inactive =
/// secondary label, no fill; hover = a faint fill. Colors are theme-derived.
@MainActor
final class CompanionTabButton: NSButton {
    let tool: CompanionTool

    var isActive = false { didSet { updateAppearance() } }
    private var isHovered = false { didSet { updateAppearance() } }
    private var isDark = false

    init(tool: CompanionTool) {
        self.tool = tool
        super.init(frame: .zero)
        let symbol = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        image = symbol
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.cornerRadius = 6
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height = 26
        return size
    }

    func applyTheme(isDark: Bool) {
        self.isDark = isDark
        updateAppearance()
    }

    private func updateAppearance() {
        let tint: NSColor = isDark ? .white : .black
        let fill: NSColor?
        let contentColor: NSColor
        if isActive {
            fill = tint.withAlphaComponent(0.09)
            contentColor = .labelColor
        } else if isHovered {
            fill = tint.withAlphaComponent(0.05)
            contentColor = .secondaryLabelColor
        } else {
            fill = nil
            contentColor = .secondaryLabelColor
        }
        layer?.backgroundColor = fill?.cgColor
        contentTintColor = contentColor
        attributedTitle = NSAttributedString(
            string: tool.title,
            attributes: [
                .foregroundColor: contentColor,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}
