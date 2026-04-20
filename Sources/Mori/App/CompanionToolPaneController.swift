import AppKit
import MoriCore
import MoriTerminal
import MoriUI

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
final class CompanionToolPaneController: NSViewController {
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let dividerView = NSView()
    private let terminalController: TerminalAreaViewController

    private(set) var activeTool: CompanionTool?

    /// Invoked when the embedded tool's process exits (e.g., user presses `q` in lazygit).
    /// The owner should close the companion pane in response.
    var onToolExited: (() -> Void)?

    init(terminalHost: TerminalHost? = nil) {
        self.terminalController = TerminalAreaViewController(terminalHost: terminalHost)
        super.init(nibName: nil, bundle: nil)
        terminalController.onSurfaceExited = { [weak self] in
            guard let self else { return }
            self.activeTool = nil
            self.onToolExited?()
        }
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

    func isFocused(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo, chromePalette: MoriChromePalette, isKeyWindow: Bool) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        let isTransparent = themeInfo.usesTransparentWindowBackground
        view.layer?.backgroundColor = isTransparent ? NSColor.clear.cgColor : chromePalette.panelBackground.nsColor.cgColor
        headerView.layer?.backgroundColor = isTransparent ? NSColor.clear.cgColor : chromePalette.headerBackground.nsColor.cgColor
        dividerView.layer?.backgroundColor = chromePalette.divider.nsColor.cgColor
        titleLabel.textColor = .secondaryLabelColor
        terminalController.updateAppearance(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
    }
}
