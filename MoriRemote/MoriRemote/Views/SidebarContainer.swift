#if os(iOS)
import SwiftUI

/// Container that adds a slide-from-left sidebar overlay to terminal content.
///
/// The sidebar can be opened by:
/// - Swiping from the left edge
/// - Tapping the sidebar button
/// - Setting `isOpen` to true
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    let content: Content

    private let sidebarWidth: CGFloat = 280

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Main content
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dimming overlay
                if isOpen || isDragging {
                    Color.black
                        .opacity(dimmingOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .allowsHitTesting(isOpen)
                }

                // Sidebar panel
                if isOpen || isDragging {
                    sidebarPanel
                        .frame(width: sidebarWidth)
                        .offset(x: sidebarOffset)
                        .transition(.identity)
                }
            }
            .gesture(edgeDragGesture(screenWidth: geo.size.width))
        }
    }

    // MARK: - Sidebar Panel

    let sidebar: () -> Sidebar

    init(isOpen: Binding<Bool>, @ViewBuilder sidebar: @escaping () -> Sidebar, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.sidebar = sidebar
        self.content = content()
    }

    private var sidebarPanel: some View {
        sidebar()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16
                )
            )
            .shadow(color: .black.opacity(0.5), radius: 20, x: 5)
    }

    // MARK: - Gesture

    private func edgeDragGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let startX = value.startLocation.x

                if isOpen {
                    // Dragging to close (swipe left on sidebar)
                    let translation = min(0, value.translation.width)
                    dragOffset = translation
                } else if startX < 30 {
                    // Edge swipe to open
                    let translation = max(0, min(sidebarWidth, value.translation.width))
                    dragOffset = translation - sidebarWidth
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.width - value.translation.width

                if isOpen {
                    // Close if dragged left enough or velocity is high
                    if value.translation.width < -60 || velocity < -200 {
                        close()
                    } else {
                        open()
                    }
                } else {
                    // Open if dragged right enough or velocity is high
                    if value.translation.width > 80 || velocity > 200 {
                        open()
                    } else {
                        close()
                    }
                }
                dragOffset = 0
            }
    }

    // MARK: - Animation Helpers

    private var sidebarOffset: CGFloat {
        if isOpen {
            return dragOffset // 0 when static, negative when dragging to close
        } else {
            return dragOffset // starts at -sidebarWidth, approaches 0 as user drags
        }
    }

    private var dimmingOpacity: Double {
        if isOpen {
            let progress = 1.0 + Double(dragOffset) / Double(sidebarWidth)
            return 0.4 * max(0, min(1, progress))
        } else {
            let progress = 1.0 + Double(dragOffset) / Double(sidebarWidth)
            return 0.4 * max(0, min(1, progress))
        }
    }

    private func open() {
        withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
            isOpen = true
            dragOffset = 0
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.25, bounce: 0.0)) {
            isOpen = false
            dragOffset = 0
        }
    }
}
#endif
