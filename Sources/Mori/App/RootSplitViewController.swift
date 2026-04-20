import AppKit
import MoriUI

@MainActor
final class RootSplitViewController: NSViewController {

    private enum DividerDragTarget {
        case sidebar
        case companion
    }

    private(set) var sidebarController: NSViewController
    private(set) var contentController: NSViewController
    private(set) var companionController: NSViewController

    private static let sidebarWidthKey = "MoriSidebarWidth"
    private static let companionWidthKey = "MoriCompanionToolPaneWidth"
    private static let sidebarMinWidth: CGFloat = 180
    private static let sidebarMaxWidth: CGFloat = 400
    private static let companionMinWidth: CGFloat = 320
    private static let dividerHitWidth: CGFloat = 8

    private let sidebarContainer = NSView()
    private let sidebarDividerView = NSView()
    private let contentContainer = NSView()
    private let companionDividerView = NSView()
    private let companionContainer = NSView()

    private var sidebarWidth: CGFloat = 280
    private var companionWidth: CGFloat = CompanionToolPaneState.defaultWidth
    private var chromePalette: MoriChromePalette = .fallback
    private var dragTarget: DividerDragTarget?
    private var collapsed = false
    private var toolPaneState = CompanionToolPaneState()

    var onCompanionWidthChanged: ((CGFloat) -> Void)?

    init(
        sidebarController: NSViewController,
        contentController: NSViewController,
        companionController: NSViewController
    ) {
        self.sidebarController = sidebarController
        self.contentController = contentController
        self.companionController = companionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        sidebarDividerView.wantsLayer = true
        companionDividerView.wantsLayer = true

        for subview in [sidebarContainer, sidebarDividerView, contentContainer, companionDividerView, companionContainer] {
            root.addSubview(subview)
        }
        self.view = root
        updateAppearance(chromePalette: chromePalette)

        embed(sidebarController, in: sidebarContainer)
        embed(contentController, in: contentContainer)
        embed(companionController, in: companionContainer)

        let savedSidebar = CGFloat(UserDefaults.standard.double(forKey: Self.sidebarWidthKey))
        if savedSidebar > 0 {
            sidebarWidth = savedSidebar.clamped(to: Self.sidebarMinWidth, Self.sidebarMaxWidth)
        }

        let savedCompanion = CGFloat(UserDefaults.standard.double(forKey: Self.companionWidthKey))
        if savedCompanion > 0 {
            companionWidth = max(Self.companionMinWidth, savedCompanion)
            toolPaneState.width = companionWidth
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateLayout()
    }

    private func resolvedCompanionWidth(given availableWidth: CGFloat) -> CGFloat {
        guard toolPaneState.isVisible else { return 0 }

        let maxAllowed = max(0, availableWidth - 1)
        let clampedWidth = max(Self.companionMinWidth, companionWidth)
        return min(clampedWidth, maxAllowed)
    }

    private func updateLayout() {
        let bounds = view.bounds
        let sidebarWidth = collapsed ? 0 : self.sidebarWidth
        let sidebarDividerWidth: CGFloat = collapsed ? 0 : 1
        let availableWidth = bounds.width - sidebarWidth - sidebarDividerWidth
        let companionVisible = toolPaneState.isVisible
        let companionDividerWidth: CGFloat = companionVisible ? 1 : 0

        let resolvedCompanionWidth = resolvedCompanionWidth(given: availableWidth)
        let contentWidth = max(0, availableWidth - companionDividerWidth - resolvedCompanionWidth)

        sidebarContainer.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        sidebarDividerView.frame = NSRect(x: sidebarWidth, y: 0, width: sidebarDividerWidth, height: bounds.height)
        contentContainer.frame = NSRect(x: sidebarWidth + sidebarDividerWidth, y: 0, width: contentWidth, height: bounds.height)
        companionDividerView.frame = NSRect(
            x: sidebarWidth + sidebarDividerWidth + contentWidth,
            y: 0,
            width: companionDividerWidth,
            height: bounds.height
        )
        companionContainer.frame = NSRect(
            x: sidebarWidth + sidebarDividerWidth + contentWidth + companionDividerWidth,
            y: 0,
            width: resolvedCompanionWidth,
            height: bounds.height
        )

        sidebarContainer.isHidden = collapsed
        sidebarDividerView.isHidden = collapsed
        contentContainer.isHidden = false
        companionContainer.isHidden = !companionVisible
        companionDividerView.isHidden = !companionVisible

        view.discardCursorRects()
        if !collapsed {
            let sidebarCenter = sidebarWidth + sidebarDividerWidth / 2
            let sidebarRect = NSRect(
                x: sidebarCenter - Self.dividerHitWidth / 2,
                y: 0,
                width: Self.dividerHitWidth,
                height: bounds.height
            )
            view.addCursorRect(sidebarRect, cursor: .resizeLeftRight)
        }

        if companionVisible {
            let companionCenter = sidebarWidth + sidebarDividerWidth + contentWidth + companionDividerWidth / 2
            let companionRect = NSRect(
                x: companionCenter - Self.dividerHitWidth / 2,
                y: 0,
                width: Self.dividerHitWidth,
                height: bounds.height
            )
            view.addCursorRect(companionRect, cursor: .resizeLeftRight)
        }
    }

    private func hitDragTarget(_ event: NSEvent) -> DividerDragTarget? {
        let x = view.convert(event.locationInWindow, from: nil).x
        if !collapsed, abs(x - sidebarWidth) <= Self.dividerHitWidth / 2 {
            return .sidebar
        }

        guard toolPaneState.isVisible else { return nil }
        let companionDividerX = companionContainer.frame.minX
        if abs(x - companionDividerX) <= Self.dividerHitWidth / 2 {
            return .companion
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if let target = hitDragTarget(event) {
            dragTarget = target
            NSCursor.resizeLeftRight.push()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragTarget else {
            super.mouseDragged(with: event)
            return
        }

        let x = view.convert(event.locationInWindow, from: nil).x
        switch dragTarget {
        case .sidebar:
            sidebarWidth = x.clamped(to: Self.sidebarMinWidth, Self.sidebarMaxWidth)
        case .companion:
            let availableWidth = view.bounds.width - sidebarVisibleWidth - sidebarDividerVisibleWidth
            let rawWidth = view.bounds.width - x - 1
            let maxAllowed = max(0, availableWidth - 1)
            companionWidth = rawWidth.clamped(to: Self.companionMinWidth, maxAllowed)
            toolPaneState.width = companionWidth
            onCompanionWidthChanged?(companionWidth)
        }
        updateLayout()
    }

    override func mouseUp(with event: NSEvent) {
        guard dragTarget != nil else {
            super.mouseUp(with: event)
            return
        }
        dragTarget = nil
        NSCursor.pop()
        saveSidebarWidth()
        saveCompanionWidth()
    }

    var isSidebarCollapsed: Bool { collapsed }
    var currentCompanionWidth: CGFloat { companionWidth }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            collapsed.toggle()
            updateLayout()
        }
    }

    func updateCompanionPane(state: CompanionToolPaneState) {
        toolPaneState = state
        companionWidth = max(Self.companionMinWidth, state.width)
        updateLayout()
    }

    func updateAppearance(chromePalette: MoriChromePalette, isTransparent: Bool = false) {
        self.chromePalette = chromePalette
        view.layer?.backgroundColor = isTransparent ? NSColor.clear.cgColor : chromePalette.windowBackground.nsColor.cgColor
        sidebarDividerView.layer?.backgroundColor = chromePalette.divider.nsColor.cgColor
        companionDividerView.layer?.backgroundColor = chromePalette.divider.nsColor.cgColor
    }

    func saveSidebarWidth() {
        guard !collapsed, sidebarWidth > 0 else { return }
        UserDefaults.standard.set(Double(sidebarWidth), forKey: Self.sidebarWidthKey)
    }

    func saveCompanionWidth() {
        guard toolPaneState.isVisible, companionWidth > 0 else { return }
        UserDefaults.standard.set(Double(companionWidth), forKey: Self.companionWidthKey)
    }

    func replaceContentController(with controller: NSViewController) {
        contentController.view.removeFromSuperview()
        contentController.removeFromParent()
        contentController = controller
        embed(controller, in: contentContainer)
        updateLayout()
    }

    private var sidebarVisibleWidth: CGFloat {
        collapsed ? 0 : sidebarWidth
    }

    private var sidebarDividerVisibleWidth: CGFloat {
        collapsed ? 0 : 1
    }

    private func embed(_ vc: NSViewController, in container: NSView) {
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: container.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            vc.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}

private extension CGFloat {
    func clamped(to minVal: CGFloat, _ maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, minVal), maxVal)
    }
}
