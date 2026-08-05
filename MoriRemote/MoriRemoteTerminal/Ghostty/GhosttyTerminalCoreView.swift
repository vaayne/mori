import GhosttyKit
import SwiftUI
import UIKit

/// Minimal composition root derived from remux's `GhosttySurfaceScreen`.
///
/// It binds one `TmuxTerminalScreenAdapter` to the active viewport, text
/// responder, input coordinator, cursor-trackpad HUD, and terminal keyboard
/// chrome. Its only construction input is the
/// adapter, so deterministic tests never need Mori SSH or persistence.
struct GhosttyTerminalCoreView: View {
    @ObservedObject private var screen: TmuxTerminalScreenAdapter
    private let onShowNavigator: () -> Void
    private let onSharedMutationRequest: (MoriRemoteTerminalSharedMutation) -> Void
    private let isInputSuspended: Bool
    private let imageUploader: MoriRemoteTerminalImageUploader?
    @State private var terminalInputController = GhosttyTerminalInputController()
    @State private var responderHandoff = GhosttyKeyboardResponderHandoff()
    @State private var trackpadDriver = GhosttyKeyboardCursorTrackpadDriver()
    @State private var trackpadFeedback = GhosttyKeyboardCursorTrackpad.FeedbackState.hidden
    @State private var compositionState = GhosttyTerminalCompositionState()
    @State private var prefixFlushTask: Task<Void, Never>?
    @State private var sessionGeneration: UInt64 = 0
    @State private var isImageAttachmentPresented = false

    init(
        screen: TmuxTerminalScreenAdapter,
        isInputSuspended: Bool = false,
        imageUploader: MoriRemoteTerminalImageUploader? = nil,
        onShowNavigator: @escaping () -> Void = {},
        onSharedMutationRequest: @escaping (MoriRemoteTerminalSharedMutation) -> Void = { _ in }
    ) {
        self.screen = screen
        self.isInputSuspended = isInputSuspended
        self.imageUploader = imageUploader
        self.onShowNavigator = onShowNavigator
        self.onSharedMutationRequest = onSharedMutationRequest
    }

    var body: some View {
        let viewportPresentation = screen.terminalViewportPresentationProjection
        let isInputAvailable = GhosttyTerminalInputAvailabilityProjection(
            isTerminalReady: screen.isInputAvailable,
            isSuspended: isInputSuspended || isImageAttachmentPresented
        ).isInputAvailable
        ZStack(alignment: .bottom) {
            // Extend behind device chrome, but retain the keyboard safe area so
            // GeometryReader reports the visible terminal viewport.
            Color.black.ignoresSafeArea(.container)
            GeometryReader { geometry in
                let liveSize = GhosttyTerminalViewportCoordinator.normalized(geometry.size)
                let effectiveSize = compositionState.viewportCoordinator.effectiveSize(liveSize: liveSize)
                GhosttySingleViewportView(
                    surfaceLookup: screen.terminalManagedSurfaceLookup,
                    projection: viewportPresentation,
                    terminalTheme: .ghosttyDefault,
                    trackpadDriver: trackpadDriver,
                    onSurfaceTap: { _ in activateTerminalInput() },
                    onWindowSwipe: { guard isInputAvailable else { return }; screen.focusAdjacentTmuxTopLevel($0) },
                    sendKeyEvent: sendTerminalKey,
                    onTrackpadFeedbackChange: { trackpadFeedback = $0 },
                    isMouseCaptured: { isInputAvailable && screen.isMouseCaptured(for: $0) },
                    submitMouseButton: { isInputAvailable ? screen.sendMouseButton(to: $0, $1) : .surfaceRejected },
                    submitMousePosition: { isInputAvailable ? screen.sendMousePosition(to: $0, $1, mods: $2) : .surfaceRejected },
                    submitMouseScroll: { isInputAvailable ? screen.sendMouseScroll(to: $0, $1) : .surfaceRejected }
                )
                .frame(width: effectiveSize.width, height: effectiveSize.height, alignment: .topLeading)
                .onAppear { reconcileViewport(liveSize) }
                .onChange(of: liveSize) { _, size in reconcileViewport(size) }
                .overlay(alignment: .center) { GhosttyKeyboardCursorTrackpadHUD(state: trackpadFeedback) }
            }

            GhosttyTerminalResponderRepresentable(
                isEnabled: isInputAvailable,
                wantsFirstResponder: isInputAvailable && compositionState.inputCoordinator.keyboardMode == .system,
                activationToken: compositionState.inputCoordinator.terminalActivationToken,
                responderHandoff: responderHandoff,
                trackpadDriver: trackpadDriver,
                keyboardAppearance: TerminalTheme.ghosttyDefault.terminalKeyboardAppearance,
                sendText: sendTerminalText,
                sendPaste: sendTerminalPaste,
                sendKeyEvent: sendTerminalKey,
                onTrackpadFeedbackChange: { trackpadFeedback = $0 },
                onFirstResponderChange: { isFirstResponder in
                    if !isFirstResponder, compositionState.inputCoordinator.keyboardMode == .system,
                       !compositionState.inputCoordinator.isDismissSystemKeyboardRequested {
                        compositionState.inputCoordinator.refocusSystemKeyboardIfActive(isInputAvailable: isInputAvailable)
                    }
                }
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GhosttyKeyboardChrome(
                keyboardMode: compositionState.inputCoordinator.keyboardMode,
                isEnabled: isInputAvailable,
                isCompact: false,
                isControlArmed: terminalInputController.isControlArmed,
                isAltArmed: terminalInputController.isAltArmed,
                imageUploader: imageUploader,
                insertImagePath: insertUploadedImagePath,
                onImagePresentationChange: { isImageAttachmentPresented = $0 },
                actions: .init(
                    showNavigator: onShowNavigator,
                    toggleKeyboard: toggleKeyboard,
                    toggleControl: { terminalInputController.toggleControl() },
                    toggleAlt: { terminalInputController.toggleAlt() },
                    requestSharedMutation: onSharedMutationRequest,
                    sendShortcut: sendTerminalShortcut,
                    sendKey: sendTerminalKey
                )
            )
            .padding(.horizontal, GhosttyKeyboardChromeSizing.dockContentHorizontalPadding)
            .padding(.vertical, GhosttyKeyboardChromeSizing.dockContentVerticalPadding)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            guard !isTerminalInputSuspended else { return }
            updateKeyboardVisibility(with: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            guard !isTerminalInputSuspended else { return }
            completeKeyboardTransition(for: .shown)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            guard !isTerminalInputSuspended else { return }
            completeKeyboardTransition(for: .hidden)
        }
        .onDisappear { cancelTransientInput() }
        .onChange(of: isTerminalInputSuspended) { _, isSuspended in
            if isSuspended { cancelTransientInput() }
        }
        .onChange(of: screen.stateTraceLabel) { oldState, newState in
            // A session lifecycle change must not let delayed or latched input
            // reach a replacement surface.
            if oldState != newState { cancelTransientInput() }
        }
    }

    private func toggleKeyboard() {
        guard isTerminalInputAvailable else { return }
        let projection = GhosttyKeyboardToggleProjection(
            keyboardMode: compositionState.inputCoordinator.keyboardMode,
            isInputAvailable: isTerminalInputAvailable
        )
        if let request = compositionState.keyboardTransitionCoordinator.transitionRequest(forToggle: projection) {
            beginKeyboardTransition(request)
        }
        compositionState.inputCoordinator.toggleKeyboard(isInputAvailable: isTerminalInputAvailable)
        if compositionState.inputCoordinator.keyboardMode == .hidden { _ = responderHandoff.transfer(to: .terminal) }
    }

    private func activateTerminalInput() {
        guard isTerminalInputAvailable else { return }
        compositionState.inputCoordinator.showSystemKeyboard(isInputAvailable: true)
    }

    private func reconcileViewport(_ size: CGSize) {
        let observation = compositionState.reconcileViewport(size)
        guard observation.didApplyStableSize else { return }
        screen.prepareInitialViewport(size: observation.effectiveSize, scale: UIScreen.main.scale)
    }

    private func updateKeyboardVisibility(with notification: Notification) {
        let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            ?? CGRect(x: 0, y: UIScreen.main.bounds.maxY, width: UIScreen.main.bounds.width, height: 0)
        if let request = compositionState.applyKeyboardVisibility(
            frameEnd: frame,
            screenBounds: UIScreen.main.bounds,
            animationDuration: (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue
        ) { beginKeyboardTransition(request) }
    }

    private func beginKeyboardTransition(_ request: GhosttyKeyboardViewportTransitionRequest) {
        let begin = compositionState.beginKeyboardTransition(request)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(begin.fallbackDelay))
            _ = compositionState.completeKeyboardTransition(token: begin.fallbackToken)
        }
    }

    private func completeKeyboardTransition(for target: GhosttyKeyboardViewportTransitionTarget) {
        let completion = GhosttyKeyboardViewportCompletionProjection(
            eventTarget: target,
            activeTransitionTarget: compositionState.viewportCoordinator.keyboardTransitionTarget,
            keyboardMode: compositionState.inputCoordinator.keyboardMode,
            isDismissSystemKeyboardRequested: compositionState.inputCoordinator.isDismissSystemKeyboardRequested,
            isInputAvailable: isTerminalInputAvailable,
            isSelectionSheetPresented: isTerminalInputSuspended,
            isAwaitingSystemKeyboardPresentation: compositionState.keyboardTransitionCoordinator.isAwaitingSystemKeyboardPresentation,
            isSceneActive: true
        )
        guard completion.action == .complete else { return }
        _ = compositionState.completeKeyboardTransition()
    }

    private func sendTerminalText(_ text: String) -> Bool {
        guard isTerminalInputAvailable else { return false }
        return terminalInputController.performTextInput(
            text,
            submit: { screen.sendInputToFocusedSurface($0).isAccepted },
            schedulePrefixFlush: schedulePrefixFlush(token:),
            // Mori selection is renderer-local; never enter server copy mode.
            enterCopyMode: { false }
        )
    }

    private func schedulePrefixFlush(token: UInt64) {
        // A new token supersedes only the old timer. Flushing the input buffer
        // here would consume the prefix that was just armed before this callback.
        prefixFlushTask?.cancel()
        let generation = sessionGeneration
        prefixFlushTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard generation == sessionGeneration,
                  isTerminalInputAvailable,
                  let input = terminalInputController.flushPendingTmuxPrefixInput(matching: token)
            else { return }
            _ = screen.sendInputToFocusedSurface(input)
        }
    }

    private func cancelPrefixFlush() {
        prefixFlushTask?.cancel()
        prefixFlushTask = nil
        _ = terminalInputController.flushPendingTmuxPrefixInput()
        sessionGeneration &+= 1
    }

    private func cancelTransientInput() {
        cancelPrefixFlush()
        terminalInputController.clearModifiers()
    }

    private func sendTerminalShortcut(_ text: String) -> Bool {
        guard isTerminalInputAvailable else { return false }
        // A menu shortcut is explicit terminal input, never the second half of
        // a previously armed tmux prefix. Flush that prefix before sending the
        // exact control/meta sequence and clear one-shot modifiers.
        prefixFlushTask?.cancel()
        prefixFlushTask = nil
        if let pendingPrefix = terminalInputController.flushPendingTmuxPrefixInput() {
            _ = screen.sendInputToFocusedSurface(pendingPrefix)
        }
        terminalInputController.clearModifiers()
        return screen.sendInputToFocusedSurface(text).isAccepted
    }

    private func sendTerminalPaste(_ text: String) -> Bool {
        guard isTerminalInputAvailable else { return false }
        return performTerminalPaste(text)
    }

    /// The image sheet intentionally suspends ordinary responder input. Its
    /// confirmed upload is the sole input allowed through that suspension.
    private func insertUploadedImagePath(_ text: String) -> Bool {
        performTerminalPaste(text)
    }

    private func performTerminalPaste(_ text: String) -> Bool {
        terminalInputController.performPaste(
            text,
            submitPendingPrefix: { screen.sendInputToFocusedSurface($0).isAccepted },
            sendPaste: { screen.sendPasteToFocusedSurface($0).isAccepted }
        )
    }

    private func sendTerminalKey(_ event: GhosttySurfaceKeyEvent) -> Bool {
        guard isTerminalInputAvailable else { return false }
        return terminalInputController.performKeyEvent(
            event,
            submitPendingPrefix: { screen.sendInputToFocusedSurface($0).isAccepted },
            sendKey: { screen.sendKeyEventToFocusedSurface($0).isAccepted }
        )
    }

    private var isTerminalInputSuspended: Bool {
        isInputSuspended || isImageAttachmentPresented
    }

    private var isTerminalInputAvailable: Bool {
        GhosttyTerminalInputAvailabilityProjection(
            isTerminalReady: screen.isInputAvailable,
            isSuspended: isTerminalInputSuspended
        ).isInputAvailable
    }
}

struct GhosttyTerminalInputAvailabilityProjection {
    static func isInputAvailable(isTerminalReady: Bool, isSuspended: Bool) -> Bool {
        isTerminalReady && !isSuspended
    }

    let isInputAvailable: Bool

    init(isTerminalReady: Bool, isSuspended: Bool) {
        isInputAvailable = Self.isInputAvailable(
            isTerminalReady: isTerminalReady,
            isSuspended: isSuspended
        )
    }
}
