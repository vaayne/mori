import SwiftUI

struct KeyboardInputView: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    @State private var draft = ""

    private let specialKeys: [(label: String, key: String)] = [
        ("Tab", "Tab"),
        ("\u{2191}", "Up"),
        ("\u{2193}", "Down"),
        ("\u{2190}", "Left"),
        ("\u{2192}", "Right"),
        ("Esc", "Escape"),
        ("Ctrl+C", "C-c"),
        ("Ctrl+D", "C-d"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Enter text", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(sendDraft)

                Button("Send") {
                    sendDraft()
                }
                .disabled(draft.isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(specialKeys, id: \.key) { entry in
                        Button(entry.label) {
                            coordinator.sendSpecialKey(entry.key)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func sendDraft() {
        let text = draft
        guard !text.isEmpty else { return }
        draft = ""
        coordinator.sendInput(text)
    }
}

#Preview {
    KeyboardInputView()
        .environment(SpikeCoordinator())
}
