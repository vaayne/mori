#if os(iOS)
import SwiftUI

/// Container that adds a slide-from-left sidebar overlay to terminal content.
///
/// The sidebar can be opened by:
/// - Swiping from the left edge of the content area
/// - Tapping the sidebar button
/// - Setting `isOpen` to true
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    let content: Content

    private let sidebarWidth: CGFloat = 280

    let sidebar: () -> Sidebar

    init(isOpen: Binding<Bool>, @ViewBuilder sidebar: @escaping () -> Sidebar, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.sidebar = sidebar
        self.content = content()
    }

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Main content — carries the edge-open gesture
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(edgeOpenGesture)

                // Dimming overlay — carries the close gesture
                if isOpen || isDragging {
                    Color.black
                        .opacity(dimmingOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .gesture(closeGesture)
                        .allowsHitTesting(isOpen)
                }

                // Sidebar panel — NO gesture, so ScrollView works freely
                if isOpen || isDragging {
                    sidebarPanel
                        .frame(width: sidebarWidth)
                        .offset(x: sidebarOffset)
                        .transition(.identity)
                }
            }
        }
    }

    // MARK: - Sidebar Panel

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

    // MARK: - Gestures

    /// Edge swipe from left to open the sidebar (only on content area).
    private var edgeOpenGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard !isOpen, value.startLocation.x < 30 else { return }
                let translation = max(0, min(sidebarWidth, value.translation.width))
                dragOffset = translation - sidebarWidth
            }
            .onEnded { value in
                guard !isOpen else { return }
                let velocity = value.predictedEndTranslation.width - value.translation.width
                if value.translation.width > 80 || velocity > 200 {
                    open()
                } else {
                    close()
                }
                dragOffset = 0
            }
    }

    /// Swipe left on dimming overlay to close the sidebar.
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .onChanged { value in
                guard isOpen else { return }
                let translation = min(0, value.translation.width)
                dragOffset = translation
            }
            .onEnded { value in
                guard isOpen else { return }
                let velocity = value.predictedEndTranslation.width - value.translation.width
                if value.translation.width < -60 || velocity < -200 {
                    close()
                } else {
                    open()
                }
                dragOffset = 0
            }
    }

    // MARK: - Animation Helpers

    private var sidebarOffset: CGFloat {
        if isOpen {
            return dragOffset
        } else {
            return dragOffset
        }
    }

    private var dimmingOpacity: Double {
        let progress = 1.0 + Double(dragOffset) / Double(sidebarWidth)
        return 0.4 * max(0, min(1, progress))
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
