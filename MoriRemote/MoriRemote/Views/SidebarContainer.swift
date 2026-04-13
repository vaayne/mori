#if os(iOS)
import SwiftUI

/// Container that adds a slide-from-left sidebar overlay to terminal content.
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    let content: Content

    private let sidebarWidth: CGFloat = 300

    let sidebar: () -> Sidebar

    init(isOpen: Binding<Bool>, @ViewBuilder sidebar: @escaping () -> Sidebar, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.sidebar = sidebar
        self.content = content()
    }

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(edgeOpenGesture)

                if isOpen || isDragging {
                    Color.black
                        .opacity(dimmingOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .gesture(closeGesture)
                        .allowsHitTesting(isOpen)
                }

                if isOpen || isDragging {
                    sidebarPanel
                        .frame(width: sidebarWidth)
                        .offset(x: sidebarOffset)
                        .transition(.identity)
                }
            }
        }
    }

    private var sidebarPanel: some View {
        sidebar()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 12
                )
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, x: 8)
    }

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

    private var sidebarOffset: CGFloat {
        dragOffset
    }

    private var dimmingOpacity: Double {
        let progress = 1.0 + Double(dragOffset) / Double(sidebarWidth)
        return 0.34 * max(0, min(1, progress))
    }

    private func open() {
        withAnimation(.easeOut(duration: 0.18)) {
            isOpen = true
            dragOffset = 0
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.16)) {
            isOpen = false
            dragOffset = 0
        }
    }
}
#endif
