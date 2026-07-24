#if os(macOS)
import AppKit

private enum TerminalShell {
    // Match Ghostty's shell-sensitive character set for terminal insertion.
    private static let escapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    static func escape(_ value: String) -> String {
        var result = value
        for character in escapeCharacters {
            result = result.replacingOccurrences(
                of: String(character),
                with: "\\\(character)"
            )
        }
        return result
    }
}

extension NSPasteboard {
    /// Returns terminal-ready text for a drop or paste operation.
    ///
    /// Local file URLs become shell-escaped absolute paths. Other items fall
    /// back to their plain-string representation. Multiple items are separated
    /// by spaces, matching Ghostty's native macOS terminal behavior.
    func moriTerminalStringContents() -> String? {
        if let url = string(forType: .URL) {
            return TerminalShell.escape(url)
        }

        let strings = (pasteboardItems ?? []).compactMap { item in
            if let propertyList = item.propertyList(forType: .fileURL),
               let fileURL = NSURL(
                   pasteboardPropertyList: propertyList,
                   ofType: .fileURL
               ) as URL?,
               fileURL.isFileURL {
                return TerminalShell.escape(fileURL.path)
            }

            return item.string(forType: .string)
        }

        return strings.isEmpty ? nil : strings.joined(separator: " ")
    }
}
#endif
