import SwiftUI
import MoriCore

/// Dashboard view showing live output from multiple agent panes in a grid.
public struct MultiPaneDashboardView: View {
    /// Each tile: (windowId, agentName, windowTitle, agentState, output)
    public struct TileData: Identifiable {
        public let id: String  // tmuxWindowId
        public let agentName: String
        public let windowTitle: String
        public let agentState: AgentState
        public let output: String

        public init(id: String, agentName: String, windowTitle: String, agentState: AgentState, output: String) {
            self.id = id
            self.agentName = agentName
            self.windowTitle = windowTitle
            self.agentState = agentState
            self.output = output
        }
    }

    let tiles: [TileData]

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 600), spacing: 8)
    ]

    public init(tiles: [TileData]) {
        self.tiles = tiles
    }

    public var body: some View {
        Group {
            if tiles.isEmpty {
                VStack(spacing: MoriTokens.Spacing.lg) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(MoriTokens.Color.muted)
                    Text(String.localized("No agents running"))
                        .font(MoriTokens.Font.windowTitle)
                        .foregroundStyle(MoriTokens.Color.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(tiles) { tile in
                            PaneTileView(
                                agentName: tile.agentName,
                                windowTitle: tile.windowTitle,
                                agentState: tile.agentState,
                                output: tile.output
                            )
                            .frame(minHeight: 200, maxHeight: 400)
                        }
                    }
                    .padding(MoriTokens.Spacing.lg)
                }
            }
        }
    }
}
