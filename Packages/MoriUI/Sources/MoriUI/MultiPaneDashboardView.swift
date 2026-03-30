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

    /// Observable model providing tiles data.
    /// Declared as a protocol-less `AnyObject` with dynamic member lookup
    /// so MoriUI doesn't depend on the app layer.
    @Observable
    public final class Model {
        public var tiles: [TileData] = []
        public init() {}
    }

    @Bindable private var model: Model

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 600), spacing: 8)
    ]

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            if model.tiles.isEmpty {
                VStack(spacing: MoriTokens.Spacing.lg) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(MoriTokens.Color.muted)
                    Text(String.localized("No agents running"))
                        .font(MoriTokens.Font.windowTitle)
                        .foregroundStyle(MoriTokens.Color.muted)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.tiles) { tile in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
