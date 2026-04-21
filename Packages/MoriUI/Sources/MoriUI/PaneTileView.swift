import SwiftUI
import MoriCore

/// A single pane tile in the multi-pane dashboard.
/// Shows a header with agent name + state badge, and scrollable monospaced output.
public struct PaneTileView: View {
    let agentName: String
    let windowTitle: String
    let projectName: String
    let worktreeName: String
    let agentState: AgentState
    let output: String

    @EnvironmentObject private var chromePaletteStore: MoriChromePaletteStore

    public init(
        agentName: String,
        windowTitle: String,
        projectName: String = "",
        worktreeName: String = "",
        agentState: AgentState,
        output: String
    ) {
        self.agentName = agentName
        self.windowTitle = windowTitle
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.agentState = agentState
        self.output = output
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: MoriTokens.Spacing.sm) {
                Image(systemName: stateIconName)
                    .font(.system(size: 10))
                    .foregroundStyle(stateColor)

                Text(agentName)
                    .font(MoriTokens.Font.sectionTitle)
                    .lineLimit(1)

                if !contextLabel.isEmpty {
                    Text(contextLabel)
                        .font(MoriTokens.Font.caption)
                        .foregroundStyle(MoriTokens.Color.muted)
                        .lineLimit(1)
                }

                Spacer()

                Text(windowTitle)
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .padding(.vertical, MoriTokens.Spacing.sm)
            .background(chromePaletteStore.palette.headerBackground.color)

            Rectangle()
                .fill(MoriTokens.Chrome.divider(chromePaletteStore.palette))
                .frame(height: 1)

            // Output
            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    Text(output.isEmpty ? String.localized("No output") : output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? MoriTokens.Color.muted : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MoriTokens.Spacing.sm)
                        .id("bottom")
                        .onChange(of: output) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                }
            }
        }
        .background(MoriTokens.Chrome.cardBackground(chromePaletteStore.palette))
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.medium)
                .stroke(MoriTokens.Chrome.divider(chromePaletteStore.palette), lineWidth: 1)
        )
    }

    private var stateIconName: String {
        switch agentState {
        case .running: return "bolt.fill"
        case .waitingForInput: return "exclamationmark.bubble.fill"
        case .error: return "xmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .none: return "terminal"
        }
    }

    private var stateColor: Color {
        switch agentState {
        case .running: return MoriTokens.Color.success
        case .waitingForInput: return MoriTokens.Color.attention
        case .error: return MoriTokens.Color.error
        case .completed: return MoriTokens.Color.success
        case .none: return MoriTokens.Color.muted
        }
    }

    /// Compact "project / worktree" label for context.
    private var contextLabel: String {
        switch (projectName.isEmpty, worktreeName.isEmpty) {
        case (false, false): return "\(projectName) / \(worktreeName)"
        case (false, true): return projectName
        case (true, false): return worktreeName
        case (true, true): return ""
        }
    }
}
