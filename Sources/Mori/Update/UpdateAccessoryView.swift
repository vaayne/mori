// MARK: - UpdateAccessoryView
// NSTitlebarAccessoryViewController wrapper hosting the SwiftUI pill.

import AppKit
import SwiftUI

/// A titlebar accessory view controller that hosts the ``UpdatePill`` SwiftUI view.
///
/// Positioned in the trailing edge of the titlebar to show an unobtrusive
/// update badge. Add to a window via `window.addTitlebarAccessoryViewController(_:)`.
final class UpdateAccessoryView: NSTitlebarAccessoryViewController {
    /// Creates an accessory view controller hosting the update pill.
    /// - Parameter model: The update view model driving the pill's state.
    init(model: UpdateViewModel) {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .trailing

        let hostingView = NSHostingView(rootView: UpdatePill(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.view = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
