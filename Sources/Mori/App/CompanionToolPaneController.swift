import AppKit
import MoriCore
import MoriTerminal

@MainActor
enum CompanionTool: String, CaseIterable {
    case yazi
    case lazygit

    var command: String {
        switch self {
        case .yazi: "yazi"
        case .lazygit: "lazygit"
        }
    }

    var title: String {
        switch self {
        case .yazi: .localized("Files")
        case .lazygit: .localized("Git")
        }
    }
}

enum CompanionToolPanePresentation {
    case closed
    case docked
    case focused
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
final class CompanionToolPaneController: NSViewController {
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let dividerView = NSView()
    private let terminalController: TerminalAreaViewController

    private(set) var activeTool: CompanionTool?

    init(terminalHost: TerminalHost? = nil) {
        self.terminalController = TerminalAreaViewController(terminalHost: terminalHost)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.wantsLayer = true

        addChild(terminalController)
        let terminalView = terminalController.view
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(headerView)
        root.addSubview(dividerView)
        root.addSubview(terminalView)
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: root.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            dividerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 1),

            terminalView.topAnchor.constraint(equalTo: dividerView.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root
    }

    func show(tool: CompanionTool, context: CompanionToolLaunchContext, focus: Bool = true) {
        activeTool = tool
        titleLabel.stringValue = tool.title
        terminalController.attachToCommand(
            identity: toolIdentity(tool: tool, context: context),
            command: tool.command,
            workingDirectory: context.workingDirectory,
            location: context.location,
            focus: focus
        )
        if focus {
            terminalController.focusCurrentSurface()
        }
    }

    func focusTool() {
        terminalController.focusCurrentSurface()
    }

    func isFocused(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo, isKeyWindow: Bool) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        headerView.layer?.backgroundColor = headerBackgroundColor(for: themeInfo).cgColor
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        titleLabel.textColor = .secondaryLabelColor
        terminalController.updateAppearance(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
    }

    private func toolIdentity(tool: CompanionTool, context: CompanionToolLaunchContext) -> String {
        "tool|\(tool.rawValue)|\(context.location.endpointKey)|\(context.workspaceID)"
    }

    private func headerBackgroundColor(for themeInfo: GhosttyThemeInfo) -> NSColor {
        let base = themeInfo.effectiveBackground.usingColorSpace(.deviceRGB) ?? themeInfo.effectiveBackground
        let blend: CGFloat = themeInfo.isDark ? 0.12 : 0.06
        let tint = themeInfo.isDark ? NSColor.white : NSColor.black
        return base.blended(withFraction: blend, of: tint) ?? base
    }
}
