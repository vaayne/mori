import SwiftUI
import MoriCore

/// A reusable submenu showing all WorkflowStatus options with a checkmark on the current status.
/// Used in context menus for worktree rows in both sidebar modes.
public struct WorkflowStatusMenu: View {
    let currentStatus: WorkflowStatus
    let onSetStatus: (WorkflowStatus) -> Void

    public init(
        currentStatus: WorkflowStatus,
        onSetStatus: @escaping (WorkflowStatus) -> Void
    ) {
        self.currentStatus = currentStatus
        self.onSetStatus = onSetStatus
    }

    public var body: some View {
        Menu("Set Status") {
            ForEach(WorkflowStatus.allCases, id: \.self) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    HStack {
                        Label(status.displayName, systemImage: status.iconName)
                        if status == currentStatus {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}
