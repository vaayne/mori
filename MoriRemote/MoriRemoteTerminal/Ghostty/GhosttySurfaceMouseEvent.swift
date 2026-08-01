import CoreGraphics
import Foundation
import GhosttyKit

struct GhosttySurfaceMouseButtonEvent: Equatable {
    enum State: Equatable {
        case press
        case release

        fileprivate var cValue: ghostty_input_mouse_state_e {
            switch self {
            case .press:
                GHOSTTY_MOUSE_PRESS
            case .release:
                GHOSTTY_MOUSE_RELEASE
            }
        }
    }

    enum Button: Equatable {
        case unknown
        case left
        case right
        case middle
        case four
        case five
        case six
        case seven
        case eight
        case nine
        case ten
        case eleven

        fileprivate var cValue: ghostty_input_mouse_button_e {
            switch self {
            case .unknown:
                GHOSTTY_MOUSE_UNKNOWN
            case .left:
                GHOSTTY_MOUSE_LEFT
            case .right:
                GHOSTTY_MOUSE_RIGHT
            case .middle:
                GHOSTTY_MOUSE_MIDDLE
            case .four:
                GHOSTTY_MOUSE_FOUR
            case .five:
                GHOSTTY_MOUSE_FIVE
            case .six:
                GHOSTTY_MOUSE_SIX
            case .seven:
                GHOSTTY_MOUSE_SEVEN
            case .eight:
                GHOSTTY_MOUSE_EIGHT
            case .nine:
                GHOSTTY_MOUSE_NINE
            case .ten:
                GHOSTTY_MOUSE_TEN
            case .eleven:
                GHOSTTY_MOUSE_ELEVEN
            }
        }
    }

    let state: State
    let button: Button
    let mods: GhosttySurfaceKeyEvent.Mods

    init(
        state: State,
        button: Button,
        mods: GhosttySurfaceKeyEvent.Mods = []
    ) {
        self.state = state
        self.button = button
        self.mods = mods
    }

    @discardableResult
    func withCValues<T>(
        _ body: (ghostty_input_mouse_state_e, ghostty_input_mouse_button_e, ghostty_input_mods_e) -> T
    ) -> T {
        body(state.cValue, button.cValue, ghostty_input_mods_e(mods.rawValue))
    }
}

struct GhosttySurfaceMouseScrollMods: Equatable {
    enum Momentum: UInt8, Equatable {
        case none = 0
        case began = 1
        case stationary = 2
        case changed = 3
        case ended = 4
        case cancelled = 5
        case mayBegin = 6
    }

    let rawValue: Int32

    var precision: Bool {
        rawValue & 0b0000_0001 != 0
    }

    var momentum: Momentum {
        let momentumBits = (rawValue >> 1) & 0b0000_0111
        return Momentum(rawValue: UInt8(momentumBits)) ?? .none
    }

    init(
        precision: Bool = false,
        momentum: Momentum = .none
    ) {
        var rawValue: Int32 = 0
        if precision {
            rawValue |= 0b0000_0001
        }
        rawValue |= Int32(momentum.rawValue) << 1
        self.rawValue = rawValue
    }

    init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    fileprivate var cValue: ghostty_input_scroll_mods_t {
        rawValue
    }
}

struct GhosttySurfaceMouseScrollEvent: Equatable {
    let deltaX: Double
    let deltaY: Double
    let mods: GhosttySurfaceMouseScrollMods

    init(
        deltaX: Double,
        deltaY: Double,
        mods: GhosttySurfaceMouseScrollMods = .init()
    ) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.mods = mods
    }
}

struct GhosttySurfaceTapGesture {
    enum Action: Equatable {
        case activateInput
        case mousePosition(CGPoint)
        case mouseButton(GhosttySurfaceMouseButtonEvent)
    }

    static func actions(
        forLocalPoint point: CGPoint,
        mouseCaptured: Bool
    ) -> [Action] {
        var actions: [Action] = [.activateInput]
        guard mouseCaptured else { return actions }

        actions.append(contentsOf: [
            .mousePosition(point),
            .mouseButton(.init(state: .press, button: .left)),
            .mouseButton(.init(state: .release, button: .left)),
        ])
        return actions
    }
}
