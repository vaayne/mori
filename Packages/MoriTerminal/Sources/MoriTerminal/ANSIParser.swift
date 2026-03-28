#if os(macOS)
import AppKit

/// Parsed segment from ANSI escape sequence processing.
enum ANSISegment {
    case text(String)
    case sgr(SGRAttributes)
    case cursorUp(Int)
    case cursorDown(Int)
    case cursorForward(Int)
    case cursorBack(Int)
    case clearScreen
    case clearLine
    case carriageReturn
    case bell
    case setTitle(String)
}
#endif

/// Attributes derived from SGR (Select Graphic Rendition) escape codes.
struct SGRAttributes {
    var reset: Bool = false
    var bold: Bool = false
    var underline: Bool = false
    var foreground: NSColor?
    var background: NSColor?
}

/// Incremental ANSI escape sequence parser.
/// Processes a stream of text and emits segments of plain text and control sequences.
struct ANSIParser {

    private enum State {
        case ground
        case escape
        case csi(params: String)
        case oscStart
        case osc(params: String)
    }

    private var state: State = .ground

    /// Parse a chunk of text, returning segments.
    mutating func parse(_ input: String) -> [ANSISegment] {
        var segments: [ANSISegment] = []
        var textBuffer = ""

        func flushText() {
            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer))
                textBuffer = ""
            }
        }

        for char in input {
            switch state {
            case .ground:
                switch char {
                case "\u{1b}":
                    flushText()
                    state = .escape
                case "\r":
                    flushText()
                    segments.append(.carriageReturn)
                case "\u{07}":
                    flushText()
                    segments.append(.bell)
                default:
                    textBuffer.append(char)
                }

            case .escape:
                switch char {
                case "[":
                    state = .csi(params: "")
                case "]":
                    state = .oscStart
                case "(", ")":
                    // Character set designation — skip next char
                    state = .ground
                default:
                    // Unknown escape — discard
                    state = .ground
                }

            case .csi(var params):
                if char.isCSIParameter {
                    params.append(char)
                    state = .csi(params: params)
                } else {
                    // Final byte — dispatch CSI sequence
                    let segment = dispatchCSI(params: params, final: char)
                    if let seg = segment {
                        segments.append(seg)
                    }
                    state = .ground
                }

            case .oscStart:
                if char == ";" {
                    state = .osc(params: "")
                } else if char.isNumber {
                    // OSC type number — skip to params
                    state = .oscStart
                } else {
                    state = .ground
                }

            case .osc(var params):
                if char == "\u{07}" || char == "\u{1b}" {
                    // BEL or ESC terminates OSC
                    if !params.isEmpty {
                        segments.append(.setTitle(params))
                    }
                    state = .ground
                } else {
                    params.append(char)
                    state = .osc(params: params)
                }
            }
        }

        flushText()
        return segments
    }

    // MARK: - CSI Dispatch

    private func dispatchCSI(params: String, final: Character) -> ANSISegment? {
        let parts = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }

        switch final {
        case "m":
            return .sgr(parseSGR(parts))
        case "A":
            return .cursorUp(parts.first ?? 1)
        case "B":
            return .cursorDown(parts.first ?? 1)
        case "C":
            return .cursorForward(parts.first ?? 1)
        case "D":
            return .cursorBack(parts.first ?? 1)
        case "J":
            let mode = parts.first ?? 0
            if mode == 2 || mode == 3 {
                return .clearScreen
            }
            return nil
        case "K":
            return .clearLine
        case "H", "f":
            // Cursor position — ignore for now
            return nil
        case "h", "l":
            // Mode set/reset — ignore
            return nil
        case "r":
            // Set scrolling region — ignore
            return nil
        default:
            return nil
        }
    }

    // MARK: - SGR

    private func parseSGR(_ codes: [Int]) -> SGRAttributes {
        var attrs = SGRAttributes()

        if codes.isEmpty || (codes.count == 1 && codes[0] == 0) {
            attrs.reset = true
            return attrs
        }

        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0:
                attrs.reset = true
            case 1:
                attrs.bold = true
            case 4:
                attrs.underline = true
            case 30...37:
                attrs.foreground = ansiColor(code - 30)
            case 38:
                // Extended foreground: 38;5;n (256-color) or 38;2;r;g;b (truecolor)
                if i + 1 < codes.count && codes[i + 1] == 5 && i + 2 < codes.count {
                    attrs.foreground = color256(codes[i + 2])
                    i += 2
                } else if i + 1 < codes.count && codes[i + 1] == 2 && i + 4 < codes.count {
                    attrs.foreground = NSColor(
                        red: CGFloat(codes[i + 2]) / 255.0,
                        green: CGFloat(codes[i + 3]) / 255.0,
                        blue: CGFloat(codes[i + 4]) / 255.0,
                        alpha: 1.0
                    )
                    i += 4
                }
            case 39:
                attrs.foreground = .white
            case 40...47:
                attrs.background = ansiColor(code - 40)
            case 48:
                // Extended background
                if i + 1 < codes.count && codes[i + 1] == 5 && i + 2 < codes.count {
                    attrs.background = color256(codes[i + 2])
                    i += 2
                } else if i + 1 < codes.count && codes[i + 1] == 2 && i + 4 < codes.count {
                    attrs.background = NSColor(
                        red: CGFloat(codes[i + 2]) / 255.0,
                        green: CGFloat(codes[i + 3]) / 255.0,
                        blue: CGFloat(codes[i + 4]) / 255.0,
                        alpha: 1.0
                    )
                    i += 4
                }
            case 49:
                attrs.background = .black
            case 90...97:
                attrs.foreground = ansiBrightColor(code - 90)
            case 100...107:
                attrs.background = ansiBrightColor(code - 100)
            default:
                break
            }
            i += 1
        }

        return attrs
    }

    // MARK: - Color Tables

    private func ansiColor(_ index: Int) -> NSColor {
        switch index {
        case 0: return .black
        case 1: return NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1)
        case 2: return NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1)
        case 3: return NSColor(red: 0.8, green: 0.8, blue: 0.0, alpha: 1)
        case 4: return NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1)
        case 5: return NSColor(red: 0.8, green: 0.0, blue: 0.8, alpha: 1)
        case 6: return NSColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1)
        case 7: return NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        default: return .white
        }
    }

    private func ansiBrightColor(_ index: Int) -> NSColor {
        switch index {
        case 0: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return NSColor(red: 0.3, green: 0.3, blue: 1.0, alpha: 1)
        case 5: return .magenta
        case 6: return .cyan
        case 7: return .white
        default: return .white
        }
    }

    private func color256(_ index: Int) -> NSColor {
        if index < 8 {
            return ansiColor(index)
        } else if index < 16 {
            return ansiBrightColor(index - 8)
        } else if index < 232 {
            // 6x6x6 color cube
            let adjusted = index - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return NSColor(
                red: CGFloat(r) / 5.0,
                green: CGFloat(g) / 5.0,
                blue: CGFloat(b) / 5.0,
                alpha: 1.0
            )
        } else {
            // Grayscale ramp
            let gray = CGFloat(index - 232) / 23.0
            return NSColor(white: gray, alpha: 1.0)
        }
    }
}

// MARK: - Character Extension

private extension Character {
    /// CSI parameter characters: digits, semicolons, and intermediate bytes.
    var isCSIParameter: Bool {
        let v = asciiValue ?? 0
        return (v >= 0x30 && v <= 0x3F) // 0-9, :, ;, <, =, >, ?
    }
}
