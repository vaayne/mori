import AppKit
import MoriTerminal

@MainActor
final class CompanionContainerController: NSViewController {
    let terminalPane: CompanionToolPaneController
    let pullRequestPane: PullRequestWebViewController

    private var activeChild: NSViewController?

    init(terminalPane: CompanionToolPaneController, pullRequestPane: PullRequestWebViewController) {
        self.terminalPane = terminalPane
        self.pullRequestPane = pullRequestPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root
        show(terminalPane)
    }

    func show(tool: CompanionTool) {
        if tool == .pullRequest {
            guard activeChild !== pullRequestPane else { return }
            swap(to: pullRequestPane)
        } else {
            guard activeChild !== terminalPane else { return }
            swap(to: terminalPane)
        }
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo, isKeyWindow: Bool) {
        terminalPane.updateAppearance(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
        pullRequestPane.updateAppearance(themeInfo: themeInfo)
    }

    private func show(_ child: NSViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        activeChild = child
    }

    private func swap(to child: NSViewController) {
        activeChild?.view.removeFromSuperview()
        activeChild?.removeFromParent()
        show(child)
    }
}
