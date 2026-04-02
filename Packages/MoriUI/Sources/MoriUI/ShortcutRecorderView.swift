import SwiftUI
import MoriCore

// MARK: - Shortcut Formatting

extension Shortcut {
    /// Formatted display string using modifier symbols (e.g. "⌘⇧P").
    var displayString: String {
        var parts: [String] = []
        if modifiers.control { parts.append("⌃") }
        if modifiers.option { parts.append("⌥") }
        if modifiers.shift { parts.append("⇧") }
        if modifiers.command { parts.append("⌘") }
        parts.append(displayKey)
        return parts.joined()
    }

    /// Human-readable key name.
    private var displayKey: String {
        switch key {
        case "↑", "↓", "←", "→": return key
        case "↩": return key
        case "(tab)": return "⇥"
        case "(delete)": return "⌫"
        case "(space)": return "Space"
        case "(escape)": return "⎋"
        default: return key.uppercased()
        }
    }
}

// MARK: - ShortcutRecorderView

/// An inline control that displays the current shortcut and allows recording a new one.
/// Global flag indicating a recorder is actively capturing a shortcut.
/// Other key monitors (e.g. AppDelegate) should check this and pass events through.
@MainActor public var isRecordingShortcut = false

struct ShortcutRecorderView: View {

    let shortcut: Shortcut?
    let isLocked: Bool
    let onRecord: (Shortcut) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            recordButton
            if !isLocked && shortcut != nil {
                clearButton
            }
        }
    }

    // MARK: - Subviews

    private var recordButton: some View {
        Button {
            if !isLocked {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text(String.localized("Press keys…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let shortcut {
                    Text(shortcut.displayString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(isLocked ? .tertiary : .primary)
                } else {
                    Text(String.localized("Unassigned"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 80)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording
                          ? Color.accentColor.opacity(0.15)
                          : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording
                                  ? Color.accentColor.opacity(0.5)
                                  : Color.primary.opacity(0.1),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .onDisappear { stopRecording() }
    }

    private var clearButton: some View {
        Button {
            onClear()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(String.localized("Unassign shortcut"))
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        MoriUI.isRecordingShortcut = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        MoriUI.isRecordingShortcut = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels recording
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Ignore bare modifier keys
        let modifiers = KeyModifiers(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )

        // Require at least one modifier for non-function keys
        let isFunctionKey = [48, 36, 51, 53, 123, 124, 125, 126].contains(event.keyCode)
        if !isFunctionKey && modifiers == .none {
            return
        }

        let (key, keyCode) = resolveKey(from: event)
        let shortcut = Shortcut(key: key, keyCode: keyCode, modifiers: modifiers)

        stopRecording()
        onRecord(shortcut)
    }

    private func resolveKey(from event: NSEvent) -> (String, UInt16?) {
        switch event.keyCode {
        case 123: return ("←", 123)
        case 124: return ("→", 124)
        case 125: return ("↓", 125)
        case 126: return ("↑", 126)
        case 36: return ("↩", 36)
        case 48: return ("(tab)", 48)
        case 51: return ("⌫", 51)
        case 53: return ("(escape)", 53)
        default:
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            return (chars, nil)
        }
    }
}
