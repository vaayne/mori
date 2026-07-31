import Foundation
import GhosttyKit
import QuartzCore
import SwiftUI
import UIKit

/// Native key event: Ghostty expects Darwin virtual key codes, not its public
/// GHOSTTY_KEY enum. Text from the software keyboard uses input(), never key().
struct GhosttySurfaceKeyEvent: Equatable {
    struct Mods: OptionSet, Equatable { let rawValue: UInt32
        static let shift = Self(rawValue: GHOSTTY_MODS_SHIFT.rawValue)
        static let ctrl = Self(rawValue: GHOSTTY_MODS_CTRL.rawValue)
        static let alt = Self(rawValue: GHOSTTY_MODS_ALT.rawValue)
        static let `super` = Self(rawValue: GHOSTTY_MODS_SUPER.rawValue)
    }
    let keyCode: UInt32
    let mods: Mods
    init(_ keyCode: UInt32, mods: Mods = []) { self.keyCode = keyCode; self.mods = mods }
    static let backspace = Self(0x33)
    static let enter = Self(0x24)
    static let up = Self(0x7E)
    static let down = Self(0x7D)
    static let left = Self(0x7B)
    static let right = Self(0x7C)
    static let tab = Self(0x30)
    static let escape = Self(0x35)
    static let forwardDelete = Self(0x75)
    static let home = Self(0x73)
    static let end = Self(0x77)
    static let pageUp = Self(0x74)
    static let pageDown = Self(0x79)

    func withCValue<T>(_ body: (ghostty_input_key_s) -> T) -> T {
        var value = ghostty_input_key_s()
        value.action = GHOSTTY_ACTION_PRESS
        value.keycode = keyCode
        value.mods = ghostty_input_mods_e(mods.rawValue)
        return body(value)
    }
}

/// Small, deterministic cap used by the local scroll view.  It protects the
/// renderer from a UIKit deceleration dumping an unbounded history jump.
/// Hardware control combinations become terminal bytes rather than UIKit menu
/// shortcuts. Physical navigation keys remain native Ghostty key events.
@MainActor enum GhosttyTerminalHardwareCommandMapping {
    enum Command: Equatable { case key(GhosttySurfaceKeyEvent), text(String) }
    static func command(characters: String, keyCode: UIKeyboardHIDUsage, modifiers: UIKeyModifierFlags) -> Command? {
        let mods = GhosttyTerminalResponderView.modifiers(modifiers)
        let keys: [UIKeyboardHIDUsage: GhosttySurfaceKeyEvent] = [.keyboardDeleteOrBackspace: .backspace, .keyboardReturnOrEnter: .enter, .keyboardTab: .tab, .keyboardEscape: .escape, .keyboardDeleteForward: .forwardDelete, .keyboardHome: .home, .keyboardEnd: .end, .keyboardPageUp: .pageUp, .keyboardPageDown: .pageDown, .keyboardUpArrow: .up, .keyboardDownArrow: .down, .keyboardLeftArrow: .left, .keyboardRightArrow: .right]
        if let key = keys[keyCode] { return .key(.init(key.keyCode, mods: mods)) }
        guard !characters.isEmpty, !modifiers.contains(.command) else { return nil }
        if modifiers.contains(.control), characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first {
            // UIKit may already translate Ctrl+C (and friends) to a control
            // byte. Preserve it; translating a second time corrupts NUL/ETX.
            if scalar.value < 0x20 { return .text(characters) }
            if scalar.value == 0x20 { return .text("\0") } // Ctrl+Space
            if scalar.value <= 0x7F { return .text(String(UnicodeScalar(scalar.value & 0x1F)!)) }
        }
        guard !modifiers.contains(.control) else { return nil }
        return .text(characters)
    }
}

/// Pure state prevents marked CJK composition from being sent twice: updates
/// replace marked text, and only the final commit is emitted.
struct GhosttyMarkedTextComposition: Equatable {
    private(set) var marked = ""
    var isActive: Bool { !marked.isEmpty }
    mutating func update(_ text: String?) { marked = text ?? "" }
    mutating func commit(_ text: String) -> String? {
        let output = text.isEmpty ? marked : text
        marked = ""
        return output.isEmpty ? nil : output
    }
}

struct GhosttyScrollProjection: Equatable {
    func synchronize(currentOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, followsBottom: Bool) -> CGFloat {
        followsBottom ? max(0, contentHeight - viewportHeight) : min(currentOffset, max(0, contentHeight - viewportHeight))
    }
}

struct GhosttyScrollDeltaBudget {
    private(set) var available: Double
    private var last: TimeInterval?
    let unitsPerSecond: Double
    let burstSeconds: Double

    init(unitsPerSecond: Double = 120, burstSeconds: Double = 0.08) {
        self.unitsPerSecond = unitsPerSecond
        self.burstSeconds = burstSeconds
        available = unitsPerSecond * burstSeconds
    }

    mutating func clamp(_ delta: Double, now: TimeInterval) -> Double {
        if let last { available = min(unitsPerSecond * burstSeconds, available + max(0, now - last) * unitsPerSecond) }
        last = now
        let amount = min(abs(delta), available)
        available -= amount
        return delta < 0 ? -amount : amount
    }
}

@MainActor
final class GhosttyManagedSurfaceRegistry {
    private var surfaces: [TmuxPaneID: TmuxPaneSurface] = [:]
    func register(_ surface: TmuxPaneSurface) { surfaces[surface.paneID] = surface }
    func unregister(_ surface: TmuxPaneSurface) { if surfaces[surface.paneID] === surface { surfaces.removeValue(forKey: surface.paneID) } }
    func surface(for paneID: TmuxPaneID) -> TmuxPaneSurface? { surfaces[paneID] }
}

/// Main-actor owner of one real CAMetal Ghostty renderer.  The controller's
/// unregister completion is the ownership fence: native memory is never freed
/// before it has stopped publishing terminal_changed callbacks.
@MainActor
final class TmuxPaneSurface {
    let paneID: TmuxPaneID
    let view: GhosttySurfaceView
    private let app: ghostty_app_t
    private let controller: TmuxSessionController
    private let terminal: TmuxSessionController.RetainedTerminal
    private let callbackBox: CallbackBox
    private var surface: ghostty_terminal_surface_t?
    private var closed = false
    private var visible = false
    private var focused = false
    private var displayLink: CADisplayLink?
    private var lastMetrics: (UInt32, UInt32, CGFloat)?
    private(set) var drawCount = 0
    private(set) var lastRendererResult: ghostty_terminal_surface_result_e = GHOSTTY_TERMINAL_SURFACE_RESULT_OK
    var onTerminalActivity: (@MainActor () -> Void)?

    private final class CallbackBox: @unchecked Sendable {
        weak var controller: TmuxSessionController?
        weak var owner: TmuxPaneSurface?
        let paneID: TmuxPaneID
        init(controller: TmuxSessionController, paneID: TmuxPaneID) { self.controller = controller; self.paneID = paneID }
        static let write: ghostty_terminal_surface_write_cb = { userdata, bytes, count in
            guard let userdata, let bytes, count > 0 else { return false }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            // This is the only outbound path. input/key/paste each cause one
            // callback; sending again from the responder would duplicate bytes.
            box.controller?.sendInput(Data(bytes: bytes, count: count), to: box.paneID)
            return box.controller != nil
        }
        static let health: ghostty_terminal_surface_renderer_health_cb = { userdata, health in
            guard health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY, let userdata else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { box.owner?.rendererFailed() }
        }
    }

    static func create(
        app: ghostty_app_t,
        controller: TmuxSessionController,
        terminal: TmuxSessionController.RetainedTerminal,
        config base: ghostty_terminal_surface_config_s,
        size: CGSize,
        completion: @escaping @MainActor (TmuxPaneSurface?) -> Void
    ) {
        let view = GhosttySurfaceView(frame: CGRect(origin: .zero, size: size))
        let box = CallbackBox(controller: controller, paneID: terminal.paneID)
        let scale = max(UIScreen.main.scale, 1)
        var config = base
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(uiview: Unmanaged.passUnretained(view).toOpaque()))
        config.userdata = Unmanaged.passUnretained(box).toOpaque()
        config.write_cb = CallbackBox.write
        config.renderer_health_cb = CallbackBox.health
        config.scale_factor = Double(scale)
        config.font_size = 14
        config.width_px = UInt32(max(1, (size.width * scale).rounded()))
        config.height_px = UInt32(max(1, (size.height * scale).rounded()))
        config.visible = false
        config.focused = false
        var handle: ghostty_terminal_surface_t?
        guard ghostty_terminal_surface_new(app, terminal.handle, &config, &handle) == GHOSTTY_TERMINAL_SURFACE_RESULT_OK, let handle else { completion(nil); return }
        let pane = TmuxPaneSurface(app: app, controller: controller, terminal: terminal, view: view, callbackBox: box, surface: handle)
        box.owner = pane
        view.drawSurface = { [weak pane] in pane?.draw() }
        controller.registerSurface(paneID: terminal.paneID, surface: handle) { result in
            guard case .success = result else { pane.freeUnregistered(); completion(nil); return }
            pane.startDrawLoop()
            pane.update(size: size)
            completion(pane)
        }
    }

    private init(app: ghostty_app_t, controller: TmuxSessionController, terminal: TmuxSessionController.RetainedTerminal, view: GhosttySurfaceView, callbackBox: CallbackBox, surface: ghostty_terminal_surface_t) {
        self.app = app; self.controller = controller; self.terminal = terminal; self.view = view; self.callbackBox = callbackBox; self.surface = surface; paneID = terminal.paneID
    }

    func setVisible(_ next: Bool) {
        guard !closed, visible != next, let surface else { return }
        visible = next
        _ = ghostty_terminal_surface_set_visible(surface, next)
        displayLink?.isPaused = !next
        if next { setNeedsDraw() }
    }

    func setFocused(_ next: Bool) {
        guard !closed, focused != next, let surface else { return }
        focused = next
        _ = ghostty_terminal_surface_set_focused(surface, next)
    }

    func update(size: CGSize) {
        guard let surface, !closed else { return }
        let scale = max(view.window?.screen.scale ?? view.contentScaleFactor, 1)
        let width = UInt32(max(1, (size.width * scale).rounded()))
        let height = UInt32(max(1, (size.height * scale).rounded()))
        guard lastMetrics?.0 != width || lastMetrics?.1 != height || lastMetrics?.2 != scale else { return }
        lastMetrics = (width, height, scale)
        view.frame = CGRect(origin: .zero, size: size)
        view.contentScaleFactor = scale
        view.alignGhosttyRendererSublayers()
        _ = ghostty_terminal_surface_set_size(surface, width, height)
        setNeedsDraw()
    }

    @discardableResult func input(_ text: String) -> Bool { withBytes(text) { ghostty_terminal_surface_input($0, $1, $2) } }
    @discardableResult func paste(_ text: String) -> Bool { withBytes(text) { ghostty_terminal_surface_paste($0, $1, $2) } }
    @discardableResult func key(_ event: GhosttySurfaceKeyEvent) -> Bool {
        guard let surface, !closed else { return false }
        return event.withCValue { accepted(ghostty_terminal_surface_key(surface, $0)) }
    }

    func selectWord(at point: CGPoint) { guard let surface, !closed else { return }; var snapshot = ghostty_terminal_surface_selection_snapshot_s(); _ = ghostty_terminal_surface_select_word(surface, point.x * view.contentScaleFactor, point.y * view.contentScaleFactor, &snapshot); setNeedsDraw() }
    func clearSelection() { guard let surface, !closed else { return }; var snapshot = ghostty_terminal_surface_selection_snapshot_s(); _ = ghostty_terminal_surface_clear_selection(surface, &snapshot); setNeedsDraw() }
    func copySelection() -> String? {
        guard let surface, !closed else { return nil }; var text = ghostty_text_s()
        guard ghostty_terminal_surface_read_selection(surface, &text) == GHOSTTY_TERMINAL_SURFACE_INPUT_SENT else { return nil }
        defer { _ = ghostty_terminal_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), as: UTF8.self)
    }

    func interactionState() -> ghostty_terminal_surface_interaction_state_s { guard let surface, !closed else { return .init() }; var state = ghostty_terminal_surface_interaction_state_s(); _ = ghostty_terminal_surface_interaction_state(surface, &state); return state }
    func scroll(to row: UInt64, offset: Double) { guard let surface, !closed else { return }; var state = ghostty_terminal_surface_interaction_state_s(); _ = ghostty_terminal_surface_scroll_to_position(surface, row, offset, &state); setNeedsDraw() }

    func terminalChanged() {
        guard let surface, !closed else { return }
        lastRendererResult = ghostty_terminal_surface_terminal_changed(surface)
        setNeedsDraw(); onTerminalActivity?()
    }

    func rendererDiagnostics() -> String {
        "visible=\(visible) focused=\(focused) draws=\(drawCount) health=\(view.rendererHealthy) last_result=\(lastRendererResult.rawValue) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) scale=\(view.contentScaleFactor)"
    }

    private func withBytes(_ text: String, _ operation: (ghostty_terminal_surface_t, UnsafePointer<UInt8>?, Int) -> ghostty_terminal_surface_input_result_e) -> Bool {
        guard let surface, !closed, !text.isEmpty else { return false }
        let result: ghostty_terminal_surface_input_result_e = text.utf8.withContiguousStorageIfAvailable { operation(surface, $0.baseAddress, $0.count) } ?? Array(text.utf8).withUnsafeBufferPointer { operation(surface, $0.baseAddress, $0.count) }
        return accepted(result)
    }
    private func accepted(_ result: ghostty_terminal_surface_input_result_e) -> Bool { result == GHOSTTY_TERMINAL_SURFACE_INPUT_SENT || result == GHOSTTY_TERMINAL_SURFACE_INPUT_CONSUMED_NO_OUTPUT }
    private func setNeedsDraw() { view.setNeedsDisplay() }
    private func draw() {
        guard visible, let surface, !closed else { return }
        ghostty_app_tick(app)
        lastRendererResult = ghostty_terminal_surface_draw(surface)
        if lastRendererResult == GHOSTTY_TERMINAL_SURFACE_RESULT_OK { drawCount += 1; onTerminalActivity?() }
    }
    private func startDrawLoop() { let link = CADisplayLink(target: self, selector: #selector(tick)); link.add(to: .main, forMode: .common); link.isPaused = true; displayLink = link }
    @objc private func tick() { draw() }
    private func rendererFailed() { guard !closed else { return }; view.rendererHealthy = false; setVisible(false) }
    private func freeUnregistered() { displayLink?.invalidate(); displayLink = nil; callbackBox.owner = nil; if let surface { ghostty_terminal_surface_free(surface) }; surface = nil; closed = true }

    func close(_ completion: @escaping @MainActor () -> Void = {}) {
        guard !closed else { completion(); return }
        closed = true; displayLink?.invalidate(); displayLink = nil; callbackBox.owner = nil
        guard let surface else { completion(); return }
        controller.unregisterSurface(paneID: paneID, surface: surface) { [weak self] in
            // unregister completion is the fence for every queued terminal_changed.
            ghostty_terminal_surface_free(surface); self?.surface = nil; completion()
        }
    }
}

@MainActor
final class GhosttyTerminalResponderView: UIView, UIKeyInput, UITextInputTraits {
    weak var pane: TmuxPaneSurface?
    private var composition = GhosttyMarkedTextComposition()
    lazy var floatingCursorTokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    weak var inputDelegate: UITextInputDelegate?
    var hasMarkedText: Bool { composition.isActive }
    override var canBecomeFirstResponder: Bool { pane != nil }
    var hasText: Bool { true }
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    func insertText(_ text: String) { submitCommittedText(text) }
    /// Called by the UITextInput shim when UIKit updates a CJK marked range.
    func updateMarkedText(_ text: String?) { composition.update(text) }
    func commitMarkedText() { if let committed = composition.commit("") { _ = pane?.input(committed.replacingOccurrences(of: "\n", with: "\r")) } }
    private func submitCommittedText(_ text: String) { if let committed = composition.commit(text) { _ = pane?.input(committed.replacingOccurrences(of: "\n", with: "\r")) } }
    func deleteBackward() { _ = pane?.key(.backspace) }
    override func paste(_ sender: Any?) { if let text = UIPasteboard.general.string { _ = pane?.paste(text) } }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let command = Self.command(for: key) else { unhandled.insert(press); continue }
            switch command { case .key(let event): _ = pane?.key(event); case .text(let text): _ = pane?.input(text) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    enum Command { case key(GhosttySurfaceKeyEvent), text(String) }
    static func command(for key: UIKey) -> Command? { GhosttyTerminalHardwareCommandMapping.command(characters: key.characters, keyCode: key.keyCode, modifiers: key.modifierFlags).map { switch $0 { case .key(let key): .key(key); case .text(let text): .text(text) } } }
    static func modifiers(_ input: UIKeyModifierFlags) -> GhosttySurfaceKeyEvent.Mods { var result: GhosttySurfaceKeyEvent.Mods = []; if input.contains(.shift) { result.insert(.shift) }; if input.contains(.control) { result.insert(.ctrl) }; if input.contains(.alternate) { result.insert(.alt) }; if input.contains(.command) { result.insert(.super) }; return result }
}

/// UIKit requires a UITextInput document to drive IME/floating-cursor paths.
/// This virtual one-character document never represents terminal contents;
/// marked text stays local until UIKit commits it through unmark/replace/insert.
final class GhosttyVirtualTextPosition: UITextPosition {
    let offset: Int
    init(_ offset: Int) { self.offset = offset; super.init() }
}

final class GhosttyVirtualTextRange: UITextRange {
    let from: GhosttyVirtualTextPosition
    let to: GhosttyVirtualTextPosition
    init(_ from: GhosttyVirtualTextPosition, _ to: GhosttyVirtualTextPosition) { self.from = from; self.to = to; super.init() }
    override var start: UITextPosition { from }
    override var end: UITextPosition { to }
    override var isEmpty: Bool { from.offset == to.offset }
}

extension GhosttyTerminalResponderView: UITextInput {
    var selectedTextRange: UITextRange? {
        get { GhosttyVirtualTextRange(GhosttyVirtualTextPosition(1), GhosttyVirtualTextPosition(1)) }
        set { _ = newValue }
    }
    var markedTextRange: UITextRange? {
        guard hasMarkedText else { return nil }
        return GhosttyVirtualTextRange(GhosttyVirtualTextPosition(0), GhosttyVirtualTextPosition(1))
    }
    var markedTextStyle: [NSAttributedString.Key: Any]? { get { nil } set { _ = newValue } }
    var beginningOfDocument: UITextPosition { GhosttyVirtualTextPosition(0) }
    var endOfDocument: UITextPosition { GhosttyVirtualTextPosition(1) }
    var tokenizer: UITextInputTokenizer { floatingCursorTokenizer }
    var selectionAffinity: UITextStorageDirection { get { .forward } set { _ = newValue } }

    func text(in range: UITextRange) -> String? {
        guard let range = range as? GhosttyVirtualTextRange, range.from.offset >= 0, range.to.offset <= 1 else { return nil }
        return range.isEmpty ? "" : " "
    }
    func replace(_ range: UITextRange, withText text: String) { _ = range; submitCommittedText(text) }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) { _ = selectedRange; updateMarkedText(markedText) }
    func unmarkText() { commitMarkedText() }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = fromPosition as? GhosttyVirtualTextPosition, let to = toPosition as? GhosttyVirtualTextPosition else { return nil }
        return GhosttyVirtualTextRange(from, to)
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? GhosttyVirtualTextPosition else { return nil }
        return GhosttyVirtualTextPosition(max(0, min(1, position.offset + offset)))
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? { self.position(from: position, offset: offset) }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let lhs = position as? GhosttyVirtualTextPosition, let rhs = other as? GhosttyVirtualTextPosition else { return .orderedSame }
        return lhs.offset == rhs.offset ? .orderedSame : lhs.offset < rhs.offset ? .orderedAscending : .orderedDescending
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { guard let lhs = from as? GhosttyVirtualTextPosition, let rhs = toPosition as? GhosttyVirtualTextPosition else { return 0 }; return rhs.offset - lhs.offset }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? { _ = direction; return range.end }
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? { _ = direction; guard let position = position as? GhosttyVirtualTextPosition else { return nil }; return GhosttyVirtualTextRange(position, position) }
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection { _ = (position, direction); return .natural }
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) { _ = (writingDirection, range) }
    func firstRect(for range: UITextRange) -> CGRect { _ = range; return .zero }
    func caretRect(for position: UITextPosition) -> CGRect { _ = position; return .zero }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { _ = range; return [] }
    func closestPosition(to point: CGPoint) -> UITextPosition? { _ = point; return GhosttyVirtualTextPosition(0) }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { _ = (point, range); return GhosttyVirtualTextPosition(0) }
    func characterRange(at point: CGPoint) -> UITextRange? { _ = point; let zero = GhosttyVirtualTextPosition(0); return GhosttyVirtualTextRange(zero, zero) }
}

@MainActor
final class GhosttyTerminalHostView: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let responder = GhosttyTerminalResponderView()
    private weak var pane: TmuxPaneSurface?
    private var budget = GhosttyScrollDeltaBudget()
    private var lastOffset: CGFloat = 0
    private let projection = GhosttyScrollProjection()
    private var isSynchronizingFromTerminal = false
    override init(frame: CGRect) { super.init(frame: frame); scroll.delegate = self; scroll.alwaysBounceVertical = true; scroll.showsVerticalScrollIndicator = true; addSubview(scroll); addSubview(responder); let tap = UITapGestureRecognizer(target: self, action: #selector(focus)); addGestureRecognizer(tap); let long = UILongPressGestureRecognizer(target: self, action: #selector(handleSelection(_:))); addGestureRecognizer(long) }
    required init?(coder: NSCoder) { fatalError() }
    func install(_ pane: TmuxPaneSurface) {
        self.pane = pane
        responder.pane = pane
        pane.onTerminalActivity = { [weak self] in self?.synchronizeScrollFromTerminal() }
        if pane.view.superview !== scroll { pane.view.removeFromSuperview(); scroll.addSubview(pane.view) }
        synchronizePresentationActivity()
        setNeedsLayout()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // SwiftUI can call updateUIView before this host is attached. This is
        // the authoritative visibility transition, not install().
        synchronizePresentationActivity()
        setNeedsLayout()
    }
    private func synchronizePresentationActivity() {
        pane?.setVisible(window != nil)
        pane?.setFocused(window != nil && responder.isFirstResponder)
        pane?.view.alignGhosttyRendererSublayers()
    }
    func detach() { responder.resignFirstResponder(); pane?.onTerminalActivity = nil; pane?.setFocused(false); pane?.setVisible(false); pane = nil }
    override func layoutSubviews() { super.layoutSubviews(); scroll.frame = bounds; responder.frame = bounds; guard let pane else { return }; pane.view.frame = CGRect(origin: CGPoint(x: 0, y: scroll.contentOffset.y), size: bounds.size); pane.update(size: bounds.size); let state = pane.interactionState().scrollbar; let cellHeight = max(bounds.height / CGFloat(max(state.len, 1)), 1); scroll.contentSize = CGSize(width: bounds.width, height: max(bounds.height, CGFloat(state.total) * cellHeight)) }
    @objc private func focus() { _ = responder.becomeFirstResponder(); synchronizePresentationActivity() }
    @objc private func handleSelection(_ recognizer: UILongPressGestureRecognizer) { guard recognizer.state == .began, let pane else { return }; pane.selectWord(at: recognizer.location(in: pane.view)); if let text = pane.copySelection(), !text.isEmpty { UIPasteboard.general.string = text } }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let pane else { return }
        let state = pane.interactionState().scrollbar
        let cellHeight = max(bounds.height / CGFloat(max(state.len, 1)), 1)
        pane.view.frame.origin.y = scrollView.contentOffset.y
        guard !isSynchronizingFromTerminal else { return }
        let delta = budget.clamp(Double(scrollView.contentOffset.y - lastOffset), now: CACurrentMediaTime())
        lastOffset = scrollView.contentOffset.y
        guard delta != 0 else { return }
        let maximumRow = Double(state.total > state.len ? state.total - state.len : 0)
        let row = UInt64(max(0, min(maximumRow, floor(Double(scrollView.contentOffset.y / cellHeight)))))
        pane.scroll(to: row, offset: 0)
    }
    private func synchronizeScrollFromTerminal() {
        guard let pane else { return }
        let state = pane.interactionState().scrollbar; let cellHeight = max(bounds.height / CGFloat(max(state.len, 1)), 1)
        let height = max(bounds.height, CGFloat(state.total) * cellHeight)
        let followsBottom = scroll.contentOffset.y >= max(0, scroll.contentSize.height - bounds.height - 1)
        scroll.contentSize = CGSize(width: bounds.width, height: height)
        let offset = projection.synchronize(currentOffset: scroll.contentOffset.y, contentHeight: height, viewportHeight: bounds.height, followsBottom: followsBottom)
        isSynchronizingFromTerminal = true
        defer { isSynchronizingFromTerminal = false }
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        pane.view.frame.origin.y = offset
        lastOffset = offset
    }
}

struct TmuxPaneSurfaceView: UIViewRepresentable {
    let surface: TmuxPaneSurface?
    func makeUIView(context: Context) -> GhosttyTerminalHostView { GhosttyTerminalHostView() }
    func updateUIView(_ host: GhosttyTerminalHostView, context: Context) { if let surface { host.install(surface) } }
    static func dismantleUIView(_ uiView: GhosttyTerminalHostView, coordinator: ()) { uiView.detach(); uiView.removeFromSuperview() }
}
