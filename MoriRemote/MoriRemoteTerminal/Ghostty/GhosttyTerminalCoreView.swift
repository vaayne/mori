import GhosttyKit
import SwiftUI
import UIKit

/// Minimal composition root derived from remux's `GhosttySurfaceScreen`.
///
/// It binds one `TmuxTerminalScreenAdapter` to the active viewport, text
/// responder, input coordinator, cursor-trackpad HUD, upstream selector
/// sheets, and terminal keyboard chrome. Its only construction input is the
/// adapter, so deterministic tests never need Mori SSH or persistence.
struct GhosttyTerminalCoreView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var screen: TmuxTerminalScreenAdapter
    private let onShowSessions: () -> Void
    private let onShowLibrary: () -> Void
    private let onSharedMutationRequest: (MoriRemoteTerminalSharedMutation) -> Void
    @State private var terminalInputController = GhosttyTerminalInputController()
    @State private var responderHandoff = GhosttyKeyboardResponderHandoff()
    @State private var trackpadDriver = GhosttyKeyboardCursorTrackpadDriver()
    @State private var trackpadFeedback = GhosttyKeyboardCursorTrackpad.FeedbackState.hidden
    @State private var selectionSheet: GhosttySurfaceSelectionSheet?
    @State private var compositionState = GhosttyTerminalCompositionState()
    @State private var prefixFlushTask: Task<Void, Never>?
    @State private var sessionGeneration: UInt64 = 0

    init(
        screen: TmuxTerminalScreenAdapter,
        onShowSessions: @escaping () -> Void = {},
        onShowLibrary: @escaping () -> Void = {},
        onSharedMutationRequest: @escaping (MoriRemoteTerminalSharedMutation) -> Void = { _ in }
    ) {
        self.screen = screen
        self.onShowSessions = onShowSessions
        self.onShowLibrary = onShowLibrary
        self.onSharedMutationRequest = onSharedMutationRequest
    }

    var body: some View {
        let projection = screen.terminalScreenPresentationProjection
        let interaction = projection.interaction
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let liveSize = GhosttyTerminalViewportCoordinator.normalized(geometry.size)
                let effectiveSize = compositionState.viewportCoordinator.effectiveSize(liveSize: liveSize)
                GhosttySingleViewportView(
                    surfaceLookup: screen.terminalManagedSurfaceLookup,
                    projection: projection.viewport,
                    terminalTheme: .ghosttyDefault,
                    trackpadDriver: trackpadDriver,
                    onSurfaceTap: { _ in activateTerminalInput() },
                    onWindowSwipe: { _ = screen.focusAdjacentTmuxTopLevel($0) },
                    sendKeyEvent: sendTerminalKey,
                    onTrackpadFeedbackChange: { trackpadFeedback = $0 },
                    isMouseCaptured: { screen.isMouseCaptured(for: $0) },
                    submitMouseButton: { screen.sendMouseButton(to: $0, $1) },
                    submitMousePosition: { screen.sendMousePosition(to: $0, $1, mods: $2) },
                    submitMouseScroll: { screen.sendMouseScroll(to: $0, $1) }
                )
                .frame(width: effectiveSize.width, height: effectiveSize.height, alignment: .topLeading)
                .onAppear { reconcileViewport(liveSize) }
                .onChange(of: liveSize) { _, size in reconcileViewport(size) }
                .overlay(alignment: .center) { GhosttyKeyboardCursorTrackpadHUD(state: trackpadFeedback) }
            }

            GhosttyTerminalResponderRepresentable(
                isEnabled: interaction.isInputAvailable,
                wantsFirstResponder: compositionState.inputCoordinator.keyboardMode == .system,
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
                        compositionState.inputCoordinator.refocusSystemKeyboardIfActive(isInputAvailable: screen.terminalInteractionProjection.isInputAvailable)
                    }
                }
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GhosttyKeyboardChrome(
                keyboardMode: compositionState.inputCoordinator.keyboardMode,
                isEnabled: interaction.isInputAvailable,
                isCompact: horizontalSizeClass == .compact,
                isControlArmed: terminalInputController.isControlArmed,
                isAltArmed: terminalInputController.isAltArmed,
                windowCount: interaction.windowCount,
                paneCount: interaction.paneCount,
                actions: .init(
                    showSessions: onShowSessions,
                    showLibrary: onShowLibrary,
                    showWindows: showWindows,
                    showPanes: showPanes,
                    toggleKeyboard: toggleKeyboard,
                    toggleControl: { terminalInputController.toggleControl() },
                    toggleAlt: { terminalInputController.toggleAlt() },
                    requestSharedMutation: onSharedMutationRequest,
                    sendShortcut: sendTerminalShortcut,
                    sendKey: sendTerminalKey
                )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            updateKeyboardVisibility(with: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            completeKeyboardTransition(for: .shown)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            completeKeyboardTransition(for: .hidden)
        }
        .onDisappear { cancelTransientInput() }
        .onChange(of: screen.stateTraceLabel) { oldState, newState in
            // A session lifecycle change must not let delayed or latched input
            // reach a replacement surface.
            if oldState != newState { cancelTransientInput() }
        }
        .sheet(item: $selectionSheet) { sheet in
            switch sheet {
            case .windows(let previews):
                GhosttyWindowSelectionSheet(
                    session: previews,
                    projection: screen.windowSelectionSheetRenderProjection(),
                    sessionName: "tmux",
                    onCreateWindow: nil,
                    onSelect: { _ = screen.focusTmuxTopLevel($0) },
                    onRemoveWindow: { _ in }
                )
            case .panes(let topLevelID, let previews):
                GhosttyPaneSelectionSheet(
                    session: previews,
                    projection: screen.paneSelectionSheetRenderProjection(topLevelID: topLevelID),
                    onSplitPane: nil,
                    onStackPane: nil,
                    onSelect: { _ = screen.focusTmuxPane($0) },
                    onRemovePane: { _ in }
                )
            }
        }
    }

    private func toggleKeyboard() {
        let projection = GhosttyKeyboardToggleProjection(
            keyboardMode: compositionState.inputCoordinator.keyboardMode,
            isInputAvailable: screen.terminalInteractionProjection.isInputAvailable
        )
        if let request = compositionState.keyboardTransitionCoordinator.transitionRequest(forToggle: projection) {
            beginKeyboardTransition(request)
        }
        compositionState.inputCoordinator.toggleKeyboard(isInputAvailable: screen.terminalInteractionProjection.isInputAvailable)
        if compositionState.inputCoordinator.keyboardMode == .hidden { _ = responderHandoff.transfer(to: .terminal) }
    }

    private func activateTerminalInput() {
        guard screen.terminalInteractionProjection.isInputAvailable else { return }
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
            isInputAvailable: screen.terminalInteractionProjection.isInputAvailable,
            isSelectionSheetPresented: selectionSheet != nil,
            isAwaitingSystemKeyboardPresentation: compositionState.keyboardTransitionCoordinator.isAwaitingSystemKeyboardPresentation,
            isSceneActive: true
        )
        guard completion.action == .complete else { return }
        _ = compositionState.completeKeyboardTransition()
    }

    private func sendTerminalText(_ text: String) -> Bool {
        terminalInputController.performTextInput(
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
        terminalInputController.performPaste(
            text,
            submitPendingPrefix: { screen.sendInputToFocusedSurface($0).isAccepted },
            sendPaste: { screen.sendPasteToFocusedSurface($0).isAccepted }
        )
    }

    private func sendTerminalKey(_ event: GhosttySurfaceKeyEvent) -> Bool {
        terminalInputController.performKeyEvent(
            event,
            submitPendingPrefix: { screen.sendInputToFocusedSurface($0).isAccepted },
            sendKey: { screen.sendKeyEventToFocusedSurface($0).isAccepted }
        )
    }

    private func showWindows() {
        guard let projection = screen.windowSheetPresentationProjection() else { return }
        selectionSheet = .windows(screen.makePanePreviewSession(
            leafIDs: projection.previewLeafIDs,
            previewSizing: .windowGridForCurrentScreen
        ))
    }

    private func showPanes() {
        guard let projection = screen.selectedPaneSheetPresentationProjection() else { return }
        selectionSheet = .panes(
            topLevelID: projection.topLevelID,
            previews: screen.makePanePreviewSession(
                leafIDs: projection.previewLeafIDs,
                previewSizing: .paneGridForCurrentScreen
            )
        )
    }
}
