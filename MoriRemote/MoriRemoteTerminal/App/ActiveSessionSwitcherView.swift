import SwiftUI

/// Account-free projection used by the terminal shell. Mori's profile model is
/// intentionally adapted at the Phase-2 composition boundary, not imported.
public struct ActiveSessionSwitcherItem: Identifiable, Equatable {
    public let id: UUID
    public let sessionName: String
    public let subtitle: String
    public let isSelected: Bool
    public let isConnected: Bool
    public let lastOpenedAt: Date

    public init(id: UUID, sessionName: String, subtitle: String, isSelected: Bool, isConnected: Bool = false, lastOpenedAt: Date) {
        self.id = id
        self.sessionName = sessionName
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isConnected = isConnected
        self.lastOpenedAt = lastOpenedAt
    }
}

enum ActiveSessionSwitcherProjection {
    static func items(_ sessions: [ActiveSessionSwitcherItem]) -> [ActiveSessionSwitcherItem] {
        sessions.sorted {
            if $0.isSelected != $1.isSelected { return $0.isSelected }
            if $0.lastOpenedAt != $1.lastOpenedAt { return $0.lastOpenedAt > $1.lastOpenedAt }
            return $0.sessionName.localizedStandardCompare($1.sessionName) == .orderedAscending
        }
    }
}

public struct ActiveSessionSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    let sessions: [ActiveSessionSwitcherItem]
    let isRefreshing: Bool
    let onSelectSession: (UUID) -> Void
    let onDisconnectSession: (UUID) -> Void

    public init(
        sessions: [ActiveSessionSwitcherItem],
        isRefreshing: Bool = false,
        onSelectSession: @escaping (UUID) -> Void,
        onDisconnectSession: @escaping (UUID) -> Void
    ) {
        self.sessions = sessions
        self.isRefreshing = isRefreshing
        self.onSelectSession = onSelectSession
        self.onDisconnectSession = onDisconnectSession
    }

    public var body: some View {
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
                if session.isConnected {
                    Button(role: .destructive) { onDisconnectSession(session.id) } label: {
                        Label(String(localized: "Disconnect"), systemImage: "bolt.slash")
                    }
                }
            }
        }
        .overlay {
            if sessions.isEmpty, isRefreshing {
                ProgressView(String(localized: "Loading sessions…"))
            } else if sessions.isEmpty {
                ContentUnavailableView(String(localized: "No tmux sessions"), systemImage: "terminal")
            }
        }
    }
}
