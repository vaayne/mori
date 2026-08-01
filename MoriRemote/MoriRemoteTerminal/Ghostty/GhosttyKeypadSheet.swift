import SwiftUI

struct GhosttyKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ghosttyTerminalChromeStyle) private var chromeStyle

    let isControlArmed: Bool
    let isAltArmed: Bool
    let onAddImage: (() -> Void)?
    let actions: GhosttyKeyboardChromeActions

    private let compactColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let editColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modifierRow
                    if let onAddImage {
                        Button(action: onAddImage) {
                            Label(String(localized: "Add image"), systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(KeypadButtonStyle(active: false, accent: chromeStyle.accent))
                        .accessibilityIdentifier("terminal.keypad.add-image")
                    }
                    keySection(String(localized: "Essential"), items: essentialKeys, columns: compactColumns)
                    keySection(String(localized: "Process"), items: processKeys, columns: compactColumns)
                    keySection(String(localized: "Edit line"), items: editingKeys, columns: editColumns)
                    keySection(String(localized: "Symbols"), items: symbolKeys, columns: compactColumns)
                }
                .padding(16)
            }
            .navigationTitle(String(localized: "Keypad"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private var modifierRow: some View {
        HStack(spacing: 10) {
            modifierButton("Ctrl", active: isControlArmed, action: .control)
            modifierButton("Alt", active: isAltArmed, action: .alt)
        }
    }

    private func modifierButton(_ title: String, active: Bool, action: GhosttyKeyboardChromeActions.Action) -> some View {
        Button { _ = actions.perform(action) } label: {
            VStack(spacing: 2) {
                Text(title).font(.headline)
                Text(active ? String(localized: "One shot armed") : String(localized: "One shot"))
                    .font(.caption2)
                    .foregroundStyle(active ? chromeStyle.accent : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(KeypadButtonStyle(active: active, accent: chromeStyle.accent))
    }

    private func keySection(
        _ title: String,
        items: [KeypadItem],
        columns: [GridItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    Button { _ = actions.perform(item.action) } label: {
                        VStack(spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let detail = item.detail {
                                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(KeypadButtonStyle(active: false, accent: chromeStyle.accent))
                    .accessibilityLabel(item.accessibilityLabel)
                }
            }
        }
    }

    private var essentialKeys: [KeypadItem] {
        [
            .init("Esc", .escape), .init("Tab", .tab), .init("Shift-Tab", .shiftTab),
            .init("←", .arrowLeft, label: String(localized: "Left arrow")),
            .init("↑", .arrowUp, label: String(localized: "Up arrow")),
            .init("↓", .arrowDown, label: String(localized: "Down arrow")),
            .init("→", .arrowRight, label: String(localized: "Right arrow")),
            .init("Home", .home), .init("End", .end),
            .init("PgUp", .pageUp, label: String(localized: "Page Up")),
            .init("PgDn", .pageDown, label: String(localized: "Page Down")),
        ]
    }

    private var processKeys: [KeypadItem] {
        [
            .init("Ctrl-C", .ctrlC, detail: String(localized: "Interrupt")),
            .init("Ctrl-D", .ctrlD, detail: String(localized: "EOF")),
            .init("Ctrl-Z", .ctrlZ, detail: String(localized: "Suspend")),
            .init("Ctrl-L", .ctrlL, detail: String(localized: "Clear")),
            .init("Ctrl-R", .ctrlR, detail: String(localized: "History")),
        ]
    }

    private var editingKeys: [KeypadItem] {
        [
            .init("Ctrl-A", .ctrlA, detail: String(localized: "Line start")),
            .init("Ctrl-E", .ctrlE, detail: String(localized: "Line end")),
            .init("Ctrl-U", .ctrlU, detail: String(localized: "Delete left")),
            .init("Ctrl-K", .ctrlK, detail: String(localized: "Delete right")),
            .init("Ctrl-W", .ctrlW, detail: String(localized: "Delete word")),
            .init("Alt-B", .altB, detail: String(localized: "Previous word")),
            .init("Alt-F", .altF, detail: String(localized: "Next word")),
        ]
    }

    private var symbolKeys: [KeypadItem] {
        [.init("?", .questionMark), .init("/", .slash)]
    }
}

private struct KeypadItem: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let action: GhosttyKeyboardChromeActions.Action
    let accessibilityLabel: String

    init(
        _ title: String,
        _ action: GhosttyKeyboardChromeActions.Action,
        detail: String? = nil,
        label: String? = nil
    ) {
        id = title
        self.title = title
        self.detail = detail
        self.action = action
        accessibilityLabel = label ?? [title, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    let active: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? accent : Color.primary)
            .padding(.horizontal, 6)
            .background(
                active ? accent.opacity(0.16) : Color.primary.opacity(configuration.isPressed ? 0.11 : 0.065),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(active ? accent.opacity(0.8) : Color.primary.opacity(0.12), lineWidth: active ? 1.25 : 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
