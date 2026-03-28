import Foundation

/// Stateless parser for tmux control-mode lines.
///
/// Parses a single newline-terminated line into a `TmuxControlLine`.
/// Does **not** track `%begin/%end` block state — that is the
/// `TmuxControlClient`'s responsibility.
public enum TmuxControlParser {

    /// Parse a single line (without trailing newline) into a control-mode event.
    public static func parse(_ line: String) -> TmuxControlLine {
        guard line.hasPrefix("%") else {
            return .plainLine(line)
        }

        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let keyword = String(parts[0])
        let rest = parts.count > 1 ? String(parts[1]) : ""

        switch keyword {
        case "%output":
            return parseOutput(rest)
        case "%begin":
            return parseBlock(rest, builder: TmuxControlLine.begin)
        case "%end":
            return parseBlock(rest, builder: TmuxControlLine.end)
        case "%error":
            return parseBlock(rest, builder: TmuxControlLine.error)
        case "%exit":
            return .notification(.exit(reason: rest.isEmpty ? nil : rest))
        case "%sessions-changed":
            return .notification(.sessionsChanged)
        case "%session-changed":
            return parseSessionChanged(rest)
        case "%window-add":
            return .notification(.windowAdd(windowId: rest))
        case "%window-close":
            return .notification(.windowClose(windowId: rest))
        case "%window-renamed":
            return parseWindowRenamed(rest)
        case "%window-pane-changed":
            return parseWindowPaneChanged(rest)
        case "%layout-change":
            return parseLayoutChanged(rest)
        default:
            return .notification(.unknown(line))
        }
    }

    // MARK: - %output parsing

    /// Parse `%output %<pane-id> <escaped-data>`.
    private static func parseOutput(_ rest: String) -> TmuxControlLine {
        // Split into pane-id and data at the first space after the pane id
        guard let spaceIndex = rest.firstIndex(of: " ") else {
            // Malformed: no data portion — treat as empty output
            return .output(paneId: rest, data: Data())
        }
        let paneId = String(rest[rest.startIndex..<spaceIndex])
        let escapedData = String(rest[rest.index(after: spaceIndex)...])
        let data = unescapeOctal(escapedData)
        return .output(paneId: paneId, data: data)
    }

    // MARK: - %begin / %end / %error parsing

    /// Parse `<timestamp> <commandNumber> <flags>` into a block line.
    private static func parseBlock(
        _ rest: String,
        builder: (Int, Int, Int) -> TmuxControlLine
    ) -> TmuxControlLine {
        let fields = rest.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3,
              let timestamp = Int(fields[0]),
              let commandNumber = Int(fields[1]),
              let flags = Int(fields[2])
        else {
            // Malformed block line — treat as unknown notification
            return .notification(.unknown(rest))
        }
        return builder(timestamp, commandNumber, flags)
    }

    // MARK: - Notification parsing

    /// Parse `%session-changed $<id> <name>`.
    private static func parseSessionChanged(_ rest: String) -> TmuxControlLine {
        let fields = rest.split(separator: " ", maxSplits: 1)
        guard fields.count >= 2 else {
            return .notification(.unknown("%session-changed \(rest)"))
        }
        return .notification(.sessionChanged(sessionId: String(fields[0]), name: String(fields[1])))
    }

    /// Parse `%window-renamed @<id> <name>`.
    private static func parseWindowRenamed(_ rest: String) -> TmuxControlLine {
        let fields = rest.split(separator: " ", maxSplits: 1)
        guard fields.count >= 2 else {
            return .notification(.unknown("%window-renamed \(rest)"))
        }
        return .notification(.windowRenamed(windowId: String(fields[0]), name: String(fields[1])))
    }

    /// Parse `%window-pane-changed @<wid> %<pid>`.
    private static func parseWindowPaneChanged(_ rest: String) -> TmuxControlLine {
        let fields = rest.split(separator: " ", maxSplits: 1)
        guard fields.count >= 2 else {
            return .notification(.unknown("%window-pane-changed \(rest)"))
        }
        return .notification(.windowPaneChanged(windowId: String(fields[0]), paneId: String(fields[1])))
    }

    /// Parse `%layout-change @<wid> <layout-string>`.
    private static func parseLayoutChanged(_ rest: String) -> TmuxControlLine {
        let fields = rest.split(separator: " ", maxSplits: 1)
        guard fields.count >= 2 else {
            return .notification(.unknown("%layout-change \(rest)"))
        }
        return .notification(.layoutChanged(windowId: String(fields[0]), layout: String(fields[1])))
    }

    // MARK: - Octal unescape

    /// Unescape tmux control-mode octal sequences in `%output` payloads.
    ///
    /// tmux escapes non-printable characters and backslash as `\ooo` (exactly 3
    /// octal digits). High-bit bytes (> 0x7E) are preserved verbatim — only
    /// non-printable + backslash are escaped.
    ///
    /// Scanning: `\` followed by exactly 3 octal digits `[0-7]` → convert to
    /// byte value. Any other `\` is preserved as-is (defensive).
    public static func unescapeOctal(_ escaped: String) -> Data {
        var result = Data()
        // Work with raw UTF-8 bytes so high-bit bytes pass through untouched
        let utf8 = Array(escaped.utf8)
        let count = utf8.count
        var i = 0
        while i < count {
            let byte = utf8[i]
            if byte == UInt8(ascii: "\\") && i + 3 < count {
                let d0 = utf8[i + 1]
                let d1 = utf8[i + 2]
                let d2 = utf8[i + 3]
                if isOctalDigit(d0) && isOctalDigit(d1) && isOctalDigit(d2) {
                    let value = (d0 - 0x30) * 64 + (d1 - 0x30) * 8 + (d2 - 0x30)
                    result.append(value)
                    i += 4
                    continue
                }
            }
            result.append(byte)
            i += 1
        }
        return result
    }

    private static func isOctalDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "7")
    }
}
