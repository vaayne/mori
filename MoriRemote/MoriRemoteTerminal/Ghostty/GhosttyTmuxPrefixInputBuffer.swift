struct GhosttyTmuxPrefixInputBuffer: Equatable {
    enum Action: Equatable {
        case submit(String)
        case armPrefix(token: UInt64)
        case enterCopyMode(fallbackInput: String)
    }

    static let defaultPrefixInput = "\u{2}"

    private var pendingInput: String?
    private var flushToken: UInt64 = 0

    mutating func handleText(_ text: String) -> Action {
        if let pendingInput {
            self.pendingInput = nil
            invalidateFlushToken()

            guard text == "[" else {
                return .submit(pendingInput + text)
            }

            return .enterCopyMode(fallbackInput: pendingInput + text)
        }

        guard text == Self.defaultPrefixInput else {
            return .submit(text)
        }

        pendingInput = text
        invalidateFlushToken()
        return .armPrefix(token: flushToken)
    }

    mutating func flushPendingInput() -> String? {
        guard let pendingInput else { return nil }
        self.pendingInput = nil
        invalidateFlushToken()
        return pendingInput
    }

    mutating func flushPendingInput(matching token: UInt64) -> String? {
        guard flushToken == token else { return nil }
        return flushPendingInput()
    }

    private mutating func invalidateFlushToken() {
        flushToken &+= 1
    }
}
