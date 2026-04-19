import Foundation

/// A tmux option assignment parsed from a preset snippet.
public struct TmuxPresetAssignment: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        case session
        case window
    }

    public let scope: Scope
    public let option: String
    public let value: String

    public init(scope: Scope, option: String, value: String) {
        self.scope = scope
        self.option = option
        self.value = value
    }
}

public enum TmuxPresetParserError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedCommand(lineNumber: Int, line: String)
    case unsupportedFlag(lineNumber: Int, flag: Character, line: String)
    case missingOption(lineNumber: Int, line: String)
    case missingValue(lineNumber: Int, option: String, line: String)
    case unterminatedQuote(lineNumber: Int, line: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let lineNumber, let line):
            return "Unsupported tmux preset command on line \(lineNumber): \(line)"
        case .unsupportedFlag(let lineNumber, let flag, let line):
            return "Unsupported tmux preset flag '-\(flag)' on line \(lineNumber): \(line)"
        case .missingOption(let lineNumber, let line):
            return "Missing tmux preset option on line \(lineNumber): \(line)"
        case .missingValue(let lineNumber, let option, let line):
            return "Missing tmux preset value for option '\(option)' on line \(lineNumber): \(line)"
        case .unterminatedQuote(let lineNumber, let line):
            return "Unterminated quote in tmux preset on line \(lineNumber): \(line)"
        }
    }
}

/// Parses a small tmux config subset used for Mori-managed presets.
///
/// Supported commands:
/// - `set -g <option> <value>`
/// - `set-option -g <option> <value>`
/// - `setw -g <option> <value>`
/// - `set-window-option -g <option> <value>`
public enum TmuxPresetParser {
    public static func parse(_ source: String) throws -> [TmuxPresetAssignment] {
        try source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
                let tokens = try tokenize(line, lineNumber: index + 1)
                guard !tokens.isEmpty else { return nil }
                return try parse(tokens: tokens, lineNumber: index + 1, line: line)
            }
    }

    private static func parse(tokens: [String], lineNumber: Int, line: String) throws -> TmuxPresetAssignment {
        guard let command = tokens.first else {
            throw TmuxPresetParserError.unsupportedCommand(lineNumber: lineNumber, line: line)
        }

        switch command {
        case "set", "set-option":
            return try parseSetCommand(
                Array(tokens.dropFirst()),
                forcedScope: nil,
                lineNumber: lineNumber,
                line: line
            )
        case "setw", "set-window-option":
            return try parseSetCommand(
                Array(tokens.dropFirst()),
                forcedScope: .window,
                lineNumber: lineNumber,
                line: line
            )
        default:
            throw TmuxPresetParserError.unsupportedCommand(lineNumber: lineNumber, line: line)
        }
    }

    private static func parseSetCommand(
        _ tokens: [String],
        forcedScope: TmuxPresetAssignment.Scope?,
        lineNumber: Int,
        line: String
    ) throws -> TmuxPresetAssignment {
        var scope = forcedScope ?? .session
        var index = 0

        while index < tokens.count, tokens[index].hasPrefix("-"), tokens[index] != "-" {
            let flagToken = tokens[index].dropFirst()
            for flag in flagToken {
                switch flag {
                case "g":
                    break
                case "w":
                    scope = .window
                default:
                    throw TmuxPresetParserError.unsupportedFlag(
                        lineNumber: lineNumber,
                        flag: flag,
                        line: line
                    )
                }
            }
            index += 1
        }

        guard index < tokens.count else {
            throw TmuxPresetParserError.missingOption(lineNumber: lineNumber, line: line)
        }

        let option = tokens[index]
        let valueTokens = Array(tokens.dropFirst(index + 1))
        guard !valueTokens.isEmpty else {
            throw TmuxPresetParserError.missingValue(
                lineNumber: lineNumber,
                option: option,
                line: line
            )
        }

        return TmuxPresetAssignment(
            scope: scope,
            option: option,
            value: valueTokens.joined(separator: " ")
        )
    }

    private static func tokenize(_ line: String, lineNumber: Int) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var startedToken = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else if char == "\\" {
                    if let escaped = iterator.next() {
                        current.append(escaped)
                    }
                } else {
                    current.append(char)
                }
                continue
            }

            switch char {
            case "#":
                if !startedToken {
                    return tokens
                }
                current.append(char)
            case "\"", "'":
                quote = char
                startedToken = true
            case "\\":
                if let escaped = iterator.next() {
                    current.append(escaped)
                    startedToken = true
                }
            case " ", "\t":
                if startedToken {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                    startedToken = false
                }
            default:
                current.append(char)
                startedToken = true
            }
        }

        if let _ = quote {
            throw TmuxPresetParserError.unterminatedQuote(lineNumber: lineNumber, line: line)
        }

        if startedToken {
            tokens.append(current)
        }

        return tokens
    }
}
