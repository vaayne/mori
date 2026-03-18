import AppKit

final class RootSplitViewController: NSSplitViewController {

    // MARK: - Child controllers

    private(set) var railController: NSViewController
    private(set) var sidebarController: NSViewController
    private(set) var contentController: NSViewController

    // MARK: - Init

    init(
        railController: NSViewController,
        sidebarController: NSViewController,
        contentController: NSViewController
    ) {
        self.railController = railController
        self.sidebarController = sidebarController
        self.contentController = contentController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Rail: 60-80pt, collapsible
        let railItem = NSSplitViewItem(sidebarWithViewController: railController)
        railItem.minimumThickness = 60
        railItem.maximumThickness = 80
        railItem.canCollapse = true
        railItem.holdingPriority = .defaultHigh + 1

        // Sidebar: 200pt min, collapsible
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultHigh

        // Content: 400pt min (placeholder for terminal in Phase 4)
        let contentItem = NSSplitViewItem(contentListWithViewController: contentController)
        contentItem.minimumThickness = 400

        addSplitViewItem(railItem)
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.dividerStyle = .thin
    }

    // MARK: - Sidebar Toggle

    var isSidebarCollapsed: Bool {
        splitViewItems.count > 1 && splitViewItems[1].isCollapsed
    }

    var isRailCollapsed: Bool {
        splitViewItems.count > 0 && splitViewItems[0].isCollapsed
    }

    func toggleSidebar() {
        guard splitViewItems.count > 1 else { return }
        let collapsed = splitViewItems[1].isCollapsed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            splitViewItems[1].animator().isCollapsed = !collapsed
        }
    }

    func toggleRail() {
        guard !splitViewItems.isEmpty else { return }
        let collapsed = splitViewItems[0].isCollapsed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            splitViewItems[0].animator().isCollapsed = !collapsed
        }
    }

    func toggleAll() {
        guard splitViewItems.count > 1 else { return }
        let collapsed = splitViewItems[1].isCollapsed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            splitViewItems[0].animator().isCollapsed = !collapsed
            splitViewItems[1].animator().isCollapsed = !collapsed
        }
    }

    // MARK: - Public helpers

    func replaceContentController(with controller: NSViewController) {
        let index = 2
        removeSplitViewItem(splitViewItems[index])

        contentController = controller
        let newItem = NSSplitViewItem(contentListWithViewController: controller)
        newItem.minimumThickness = 400
        insertSplitViewItem(newItem, at: index)
    }
}
