// MARK: - UpdatePill
// Pill-shaped button for titlebar with badge and popover trigger.

import SwiftUI

/// A pill-shaped button that displays update status and provides access to update actions.
///
/// Shows a capsule-shaped button with an ``UpdateBadge`` icon and text label.
/// Clicking opens a popover with ``UpdatePopoverView`` for detailed actions.
/// Auto-dismisses the `.notFound` state after 5 seconds.
/// Only visible when state is not `.idle`.
struct UpdatePill: View {
    /// The update view model that provides the current state and information
    @ObservedObject var model: UpdateViewModel

    /// Whether the update popover is currently visible
    @State private var showPopover = false

    /// Task for auto-dismissing the "No Updates" state
    @State private var resetTask: Task<Void, Never>?

    /// Cached text width to avoid remeasuring on every render
    @State private var cachedTextWidth: CGFloat?

    /// The font used for the pill text
    private let textFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    var body: some View {
        if !model.state.isIdle {
            pillButton
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    UpdatePopoverView(model: model)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onChange(of: model.maxWidthText) { _, newText in
                    let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
                    cachedTextWidth = (newText as NSString).size(withAttributes: attributes).width
                }
                .onChange(of: model.state) { _, newState in
                    resetTask?.cancel()
                    if case .notFound(let notFound) = newState {
                        resetTask = Task { [weak model] in
                            try? await Task.sleep(for: .seconds(5))
                            guard !Task.isCancelled, let model, case .notFound = model.state else { return }
                            notFound.dismiss(from: model)
                        }
                    } else {
                        resetTask = nil
                    }
                }
        }
    }

    /// The pill-shaped button view that displays the update badge and text
    @ViewBuilder
    private var pillButton: some View {
        Button(action: {
            if case .notFound(let notFound) = model.state {
                notFound.dismiss(from: model)
            } else {
                showPopover.toggle()
            }
        }, label: {
            HStack(spacing: 6) {
                UpdateBadge(model: model)
                    .frame(width: 14, height: 14)

                Text(model.text)
                    .font(Font(textFont))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: cachedTextWidth ?? measureTextWidth(model.maxWidthText))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(model.backgroundColor)
            )
            .foregroundColor(model.foregroundColor)
            .contentShape(Capsule())
        })
        .buttonStyle(.plain)
        .help(model.text)
        .accessibilityLabel(model.text)
    }

    private func measureTextWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
        return (text as NSString).size(withAttributes: attributes).width
    }
}
