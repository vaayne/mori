import AppKit

@MainActor
final class RootSplitViewController: NSViewController {

    private(set) var sidebarController: NSViewController
    private(set) var contentController: NSViewController

    private static let widthKey = "MoriSidebarWidth"
    private static let minWidth: CGFloat = 180
    private static let maxWidth: CGFloat = 400
    private static let hitWidth: CGFloat = 8

    private let sidebarContainer = NSView()
    private let dividerView = NSView()
    private let contentContainer = NSView()
    private var sidebarWidth: CGFloat = 280
    private var isDragging = false
    private var collapsed = false

    init(sidebarController: NSViewController, contentController: NSViewController) {
        self.sidebarController = sidebarController
        self.contentController = contentController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor

        for v in [sidebarContainer, dividerView, contentContainer] {
            root.addSubview(v)
        }
        self.view = root

        embed(sidebarController, in: sidebarContainer)
        embed(contentController, in: contentContainer)

        let saved = UserDefaults.standard.double(forKey: Self.widthKey)
        if saved > 0 { sidebarWidth = saved.clamped(to: Self.minWidth, Self.maxWidth) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateLayout()
    }

    // MARK: - Layout

    private func updateLayout() {
        let b = view.bounds
        let sw: CGFloat = collapsed ? 0 : sidebarWidth
        let dw: CGFloat = collapsed ? 0 : 1

        sidebarContainer.frame = NSRect(x: 0, y: 0, width: sw, height: b.height)
        dividerView.frame = NSRect(x: sw, y: 0, width: dw, height: b.height)
        contentContainer.frame = NSRect(x: sw + dw, y: 0, width: b.width - sw - dw, height: b.height)
        sidebarContainer.isHidden = collapsed
        dividerView.isHidden = collapsed

        view.discardCursorRects()
        if !collapsed {
            let center = sw + dw / 2
            let rect = NSRect(x: center - Self.hitWidth / 2, y: 0, width: Self.hitWidth, height: b.height)
            view.addCursorRect(rect, cursor: .resizeLeftRight)
        }
    }

    // MARK: - Divider drag

    private func hitDivider(_ event: NSEvent) -> Bool {
        guard !collapsed else { return false }
        let x = view.convert(event.locationInWindow, from: nil).x
        return abs(x - sidebarWidth) <= Self.hitWidth / 2
    }

    override func mouseDown(with event: NSEvent) {
        if hitDivider(event) { isDragging = true; NSCursor.resizeLeftRight.push() }
        else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { super.mouseDragged(with: event); return }
        sidebarWidth = view.convert(event.locationInWindow, from: nil).x
            .clamped(to: Self.minWidth, Self.maxWidth)
        updateLayout()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { super.mouseUp(with: event); return }
        isDragging = false
        NSCursor.pop()
        saveSidebarWidth()
    }

    // MARK: - Public

    var isSidebarCollapsed: Bool { collapsed }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            collapsed.toggle()
            updateLayout()
        }
    }

    func saveSidebarWidth() {
        guard !collapsed, sidebarWidth > 0 else { return }
        UserDefaults.standard.set(Double(sidebarWidth), forKey: Self.widthKey)
    }

    func replaceContentController(with controller: NSViewController) {
        contentController.view.removeFromSuperview()
        contentController.removeFromParent()
        contentController = controller
        embed(controller, in: contentContainer)
        updateLayout()
    }

    // MARK: - Helpers

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

private extension Double {
    func clamped(to minVal: CGFloat, _ maxVal: CGFloat) -> CGFloat {
        CGFloat(self).clamped(to: minVal, maxVal)
    }
}
