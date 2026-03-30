import SwiftUI

/// Inline text field for replying to a waiting agent.
/// Shows a text input with send button; dismisses on submit.
public struct QuickReplyField: View {
    let onSend: (String) -> Void
    let onDismiss: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    public init(
        onSend: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onSend = onSend
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            TextField(String.localized("Reply…"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    sendIfNonEmpty()
                }
                .onExitCommand {
                    onDismiss()
                }

            Button(action: sendIfNonEmpty) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(text.isEmpty ? MoriTokens.Color.muted : MoriTokens.Color.active)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, MoriTokens.Spacing.lg)
        .padding(.vertical, MoriTokens.Spacing.sm)
        .background(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .onAppear { isFocused = true }
    }

    private func sendIfNonEmpty() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
        onDismiss()
    }
}
