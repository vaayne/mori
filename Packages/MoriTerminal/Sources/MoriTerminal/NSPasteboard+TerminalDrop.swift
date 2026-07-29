#if os(macOS)
import AppKit

private enum TerminalShell {
    // Match Ghostty's shell-sensitive character set for terminal insertion.
    private static let escapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    /// Returns `nil` for values a shell escape cannot make safe.
    ///
    /// The escape set has no answer for CR/LF: libghostty treats inserted text as a
    /// confirmed paste and turns LF into CR when bracketed paste is off, so a newline
    /// in a dropped file name would submit the rest of the value as a command.
    static func escape(_ value: String) -> String? {
        guard !value.contains(where: \.isTerminalLineBreak) else { return nil }

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

private extension Character {
    var isTerminalLineBreak: Bool { self == "\r" || self == "\n" }
}

extension NSPasteboard {
    /// Returns terminal-ready text for a drop or paste operation.
    ///
    /// Mirrors Ghostty's `performDragOperation`: the pasteboard is inspected as a
    /// whole, in order — a URL, else every file URL as a shell-escaped absolute path
    /// (space-joined in item order), else the plain string. File URLs and plain
    /// strings are never mixed. Returns `nil` when nothing can be safely inserted.
    func moriTerminalStringContents() -> String? {
        if let url = string(forType: .URL) {
            return TerminalShell.escape(url)
        }

        let filePaths = (pasteboardItems ?? []).compactMap { item -> String? in
            guard let propertyList = item.propertyList(forType: .fileURL),
                  let fileURL = NSURL(
                      pasteboardPropertyList: propertyList,
                      ofType: .fileURL
                  ) as URL?,
                  fileURL.isFileURL else { return nil }

            return fileURL.path
        }

        if !filePaths.isEmpty {
            let escaped = filePaths.compactMap(TerminalShell.escape)
            // One unsafe name poisons the whole drop; inserting the rest would
            // silently drop a file the user dragged.
            guard escaped.count == filePaths.count else { return nil }
            return escaped.joined(separator: " ")
        }

        return string(forType: .string)
    }
}
#endif
