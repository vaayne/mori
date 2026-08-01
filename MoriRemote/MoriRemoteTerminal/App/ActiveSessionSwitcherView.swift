import SwiftUI

/// Account-free projection used by the terminal shell. Mori's profile model is
/// intentionally adapted at the Phase-2 composition boundary, not imported.
struct ActiveSessionSwitcherItem: Identifiable, Equatable {
    let id: UUID
    let sessionName: String
    let subtitle: String
    let runtimeState: TerminalRuntimeState
    let isSelected: Bool
    let lastOpenedAt: Date
}

enum ActiveSessionSwitcherProjection {
    static func items(_ sessions: [ActiveSessionSwitcherItem]) -> [ActiveSessionSwitcherItem] {
        sessions.sorted {
            if $0.isSelected != $1.isSelected { return $0.isSelected }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
    }
}

struct ActiveSessionSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    let sessions: [ActiveSessionSwitcherItem]
    let onSelectSession: (UUID) -> Void
    let onDisconnectSession: (UUID) -> Void

    var body: some View {
        List(ActiveSessionSwitcherProjection.items(sessions)) { session in
            Button {
                onSelectSession(session.id)
                dismiss()
            } label: {
                VStack(alignment: .leading) {
                    Text(session.sessionName)
                    Text(session.subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .swipeActions {
                Button(role: .destructive) { onDisconnectSession(session.id) } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            }
        }
    }
}
