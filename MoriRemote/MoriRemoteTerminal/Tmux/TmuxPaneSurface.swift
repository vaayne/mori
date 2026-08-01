import Foundation
import GhosttyKit
import QuartzCore
import UIKit

/// MainActor owner of one retained canonical pane terminal and its current
/// renderer surface. Normal pane switches retain this entire object unchanged;
/// only renderer failure replaces the renderer over the same terminal and
/// UIView. Settings update the live surface in place.
@MainActor
final class TmuxPaneSurface {
    let paneID: TmuxPaneID
    let instanceID = TerminalSurfaceInstanceID()
    let view: GhosttyKitSurfaceView

    private let app: ghostty_app_t
    private let controller: TmuxSessionController
    private let terminal: TmuxSessionController.RetainedPaneTerminal
    private let callbackBox: CallbackBox
    private let failureRelay: FailureRelay
    private let onRendererFailure: (TmuxPaneID) -> Void

    private struct Renderer {
        let handle: ghostty_terminal_surface_t
        let control: GhosttyKitControlSurface
    }

    private enum Lifecycle {
        case active
        case replacing
        case closing
        case closed
    }

    private var renderer: Renderer?
    private(set) var managedSurface: GhosttyManagedSurface?
    private var lastPublishedViewportMetrics: GhosttySurfaceDisplayMetrics?
    private var presented = false
    private var sceneActive = true
    private var lifecycle = Lifecycle.active
    private var rendererFailureReported = false
    private var closeCompletions: [@MainActor @Sendable () -> Void] = []
    private var framePublicationWait: FramePublicationWait?
    private var presentationTask: Task<Void, Never>?
    private var presentationGeneration: UInt64 = 0
    private let frameRelay = FrameRelay()
    private let publishedFrameObserver = GhosttyPublishedFrameObserver()
    private var canonicalViewportMetrics: GhosttySurfaceDisplayMetrics
    private var appliedDisplayMetrics: GhosttySurfaceDisplayMetrics

    enum CreateError: Error {
        case surfaceCreationFailed(ghostty_terminal_surface_result_e)
        case registrationFailed(TmuxSessionController.SurfaceRegistrationError)
    }

    enum RendererReplacementResult: Equatable {
        case replaced
        case busy
        case failed
    }

    private final class FailureRelay {
        weak var pane: TmuxPaneSurface?
    }

    private final class FramePublicationWait: @unchecked Sendable {
        let expectedWidth: UInt32
        let expectedHeight: UInt32
        var observation: NSKeyValueObservation?
        var continuation: CheckedContinuation<Bool, Never>?

        init(expectedWidth: UInt32, expectedHeight: UInt32) {
            self.expectedWidth = expectedWidth
            self.expectedHeight = expectedHeight
        }
    }

    private final class FrameRelay: @unchecked Sendable {
        weak var pane: TmuxPaneSurface?
    }

    private final class LayerReference: @unchecked Sendable {
        weak var layer: CALayer?

        init(_ layer: CALayer) {
            self.layer = layer
        }
    }

    private final class CallbackBox: @unchecked Sendable {
        enum TrackedWriteTransport {
            case exact
            case literal
        }

        private struct TrackedWrite {
            let transport: TrackedWriteTransport
            let completion: @Sendable (Bool) -> Void
        }

        let controller: TmuxSessionController
        let paneID: TmuxPaneID
        let failureRelay: FailureRelay
        private var trackedWrite: TrackedWrite?

        init(
            controller: TmuxSessionController,
            paneID: TmuxPaneID,
            failureRelay: FailureRelay
        ) {
            self.controller = controller
            self.paneID = paneID
            self.failureRelay = failureRelay
        }

        static let writeCallback: ghostty_terminal_surface_write_cb = { userdata, pointer, count in
            // ghostty.h: write_cb fires only from terminal-surface input
            // operations on the presentation-owner thread, never from the
            // output feed. `trackedWrite` is single-threaded because of
            // this contract.
            assert(Thread.isMainThread)
            guard let userdata else { return false }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            guard count > 0 else { return true }
            guard let pointer else { return false }
            if let trackedWrite = box.trackedWrite {
                box.trackedWrite = nil
                let bytes = Data(bytes: pointer, count: count)
                let admitted = switch trackedWrite.transport {
                case .exact:
                    box.controller.sendTrackedInput(
                        paneID: box.paneID,
                        bytes,
                        completion: trackedWrite.completion
                    )
                case .literal:
                    box.controller.sendTrackedLiteralInput(
                        paneID: box.paneID,
                        bytes,
                        completion: trackedWrite.completion
                    )
                }
                if !admitted {
                    trackedWrite.completion(false)
                }
                return admitted
            }
            return box.controller.sendInput(
                paneID: box.paneID,
                Data(bytes: pointer, count: count)
            )
        }

        func performTrackedWrite(
            transport: TrackedWriteTransport,
            completion: @escaping @Sendable (Bool) -> Void,
            _ operation: () -> Bool
        ) {
            MainActor.preconditionIsolated()
            precondition(trackedWrite == nil)
            trackedWrite = TrackedWrite(transport: transport, completion: completion)
            _ = operation()
            guard trackedWrite != nil else { return }
            trackedWrite = nil
            completion(false)
        }

        static let healthCallback: ghostty_terminal_surface_renderer_health_cb = { userdata, health in
            guard health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY, let userdata else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { [weak relay = box.failureRelay] in
                MainActor.assumeIsolated { relay?.pane?.rendererDidFail() }
            }
        }
    }

    static func create(
        app: ghostty_app_t,
        controller: TmuxSessionController,
        terminal: TmuxSessionController.RetainedPaneTerminal,
        baseConfig: ghostty_terminal_surface_config_s,
        metrics: GhosttySurfaceDisplayMetrics,
        theme: TerminalTheme,
        onRendererFailure: @escaping @MainActor (TmuxPaneID) -> Void,
        completion: @escaping @MainActor (Result<TmuxPaneSurface, CreateError>) -> Void
    ) {
        let relay = FailureRelay()
        let callbackBox = CallbackBox(
            controller: controller,
            paneID: terminal.paneID,
            failureRelay: relay
        )
        let view = GhosttyKitSurfaceView(frame: CGRect(
            x: 0,
            y: 0,
            width: Double(metrics.pixelWidth) / metrics.contentScale,
            height: Double(metrics.pixelHeight) / metrics.contentScale
        ))
        view.contentScaleFactor = metrics.contentScale
        view.applyTerminalTheme(theme)

        var config = configured(
            baseConfig,
            view: view,
            metrics: metrics,
            callbackBox: callbackBox,
            visible: false,
            focused: false
        )
        var nativeSurface: ghostty_terminal_surface_t?
        let result = ghostty_terminal_surface_new(
            app,
            terminal.handle,
            &config,
            &nativeSurface
        )
        guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK, let nativeSurface else {
            completion(.failure(.surfaceCreationFailed(result)))
            return
        }
        view.alignGhosttyRendererSublayers()

        let pane = TmuxPaneSurface(
            app: app,
            controller: controller,
            terminal: terminal,
            view: view,
            surface: nativeSurface,
            metrics: metrics,
            callbackBox: callbackBox,
            failureRelay: relay,
            onRendererFailure: onRendererFailure
        )
        relay.pane = pane
        controller.registerTerminalSurface(
            paneID: terminal.paneID,
            surface: nativeSurface
        ) { result in
            switch result {
            case .success:
                completion(.success(pane))
            case .failure(let error):
                pane.destroyUnregisteredRenderer()
                completion(.failure(.registrationFailed(error)))
            }
        }
    }

    private init(
        app: ghostty_app_t,
        controller: TmuxSessionController,
        terminal: TmuxSessionController.RetainedPaneTerminal,
        view: GhosttyKitSurfaceView,
        surface: ghostty_terminal_surface_t,
        metrics: GhosttySurfaceDisplayMetrics,
        callbackBox: CallbackBox,
        failureRelay: FailureRelay,
        onRendererFailure: @escaping (TmuxPaneID) -> Void
    ) {
        self.app = app
        self.controller = controller
        self.terminal = terminal
        paneID = terminal.paneID
        self.view = view
        self.callbackBox = callbackBox
        self.failureRelay = failureRelay
        self.onRendererFailure = onRendererFailure
        canonicalViewportMetrics = metrics
        appliedDisplayMetrics = metrics
        let control = GhosttyKitControlSurface(
            surface: surface,
            scaleFactor: metrics.contentScale,
            onFailure: { [weak failureRelay] _ in
                failureRelay?.pane?.rendererDidFail()
            }
        )
        renderer = Renderer(handle: surface, control: control)
        frameRelay.pane = self
    }

    var rawSurface: ghostty_terminal_surface_t? { renderer?.handle }

    func sendPasteAwaitingCommandCompletion(_ text: String) async -> Bool {
        guard !text.isEmpty, lifecycle == .active, let renderer else { return false }
        return await performInputAwaitingCommandCompletion(transport: .literal) {
            renderer.control.sendPaste(text)
        }
    }

    func sendKeyEventAwaitingCommandCompletion(
        _ event: GhosttySurfaceKeyEvent
    ) async -> Bool {
        guard lifecycle == .active, let renderer else { return false }
        return await performInputAwaitingCommandCompletion(transport: .exact) {
            renderer.control.sendKeyEvent(event)
        }
    }

    private func performInputAwaitingCommandCompletion(
        transport: CallbackBox.TrackedWriteTransport,
        _ operation: () -> Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            callbackBox.performTrackedWrite(
                transport: transport,
                completion: { continuation.resume(returning: $0) },
                operation
            )
        }
    }

    func screenSurface(
        onDisplayUpdate: @escaping (GhosttyManagedSurface, CGSize, CGFloat) -> Void
    ) -> GhosttyManagedSurface {
        if let managedSurface {
            if renderer != nil { managedSurface.refreshInteractionState() }
            managedSurface.onDisplayUpdate = onDisplayUpdate
            return managedSurface
        }
        guard let renderer else {
            preconditionFailure("first screen surface requires a registered renderer")
        }

        let managed = GhosttyManagedSurface(
            id: instanceID.rawValue,
            view: view,
            controlSurface: renderer.control,
            paneOwner: self,
            interactionState: renderer.control.interactionState()
        )
        managed.onDisplayUpdate = onDisplayUpdate
        managedSurface = managed
        installPublishedFrameInteractionObservation()
        applyPresentationActivity()
        return managed
    }

    func setPresented(_ presented: Bool) {
        guard lifecycle != .closed, lifecycle != .closing else { return }
        self.presented = presented
        if presented {
            installPublishedFrameInteractionObservation()
            // A warm revisit may attach its retained genuine frame before a
            // newer viewport-sized frame arrives. Resize first, then make the
            // already-published pane surface visible and interactive.
            _ = applyDisplayMetrics(canonicalViewportMetrics)
        }
        applyPresentationActivity()
    }

    func setSceneActive(_ active: Bool) {
        guard lifecycle != .closed, lifecycle != .closing else { return }
        guard active != sceneActive else { return }
        sceneActive = active
        applyPresentationActivity()
    }

    func refreshInteractionState() {
        managedSurface?.refreshInteractionState()
    }

    func updateCanonicalViewportMetrics(_ metrics: GhosttySurfaceDisplayMetrics) {
        canonicalViewportMetrics = metrics
    }

    @discardableResult
    func updateDisplay(metrics: GhosttySurfaceDisplayMetrics) -> Bool {
        canonicalViewportMetrics = metrics
        return applyDisplayMetrics(metrics)
    }

    func prepareForPresentation(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard lifecycle == .active, !presented else {
            completion(false)
            return
        }
        cancelPresentationPreparation()
        presentationGeneration &+= 1
        let generation = presentationGeneration

        if hasCurrentViewportFrame() {
            completion(true)
            return
        }

        guard applyDisplayMetrics(canonicalViewportMetrics),
              let rendererLayer = GhosttyRendererLayer.find(in: view.layer)
        else {
            completion(false)
            return
        }

        let expected = canonicalViewportMetrics
        presentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let didPublish = await waitForViewportFrame(
                on: rendererLayer,
                expectedWidth: expected.pixelWidth,
                expectedHeight: expected.pixelHeight
            )
            guard presentationGeneration == generation else { return }
            presentationTask = nil
            guard !Task.isCancelled,
                  expected == canonicalViewportMetrics,
                  didPublish
            else {
                completion(false)
                return
            }
            lastPublishedViewportMetrics = expected
            completion(true)
        }
    }

    func cancelPresentationPreparation() {
        presentationGeneration &+= 1
        let hadTask = presentationTask != nil
        let hadWait = framePublicationWait != nil
        presentationTask?.cancel()
        presentationTask = nil
        if hadWait {
            // The wait owns its transient visibility and hides exactly once.
            cancelFramePublicationWait()
        } else if hadTask, !presented {
            // Publication may have completed with keep-visible immediately
            // before the MainActor task is cancelled.
            _ = renderer?.control.setVisible(false)
        }
    }

    @discardableResult
    func applyTerminalConfiguration(theme: TerminalTheme) -> Bool {
        guard lifecycle == .active, let renderer else { return false }
        let result = ghostty_terminal_surface_update_config(renderer.handle)
        guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK else {
            GhosttyRuntimeTrace.diagnostics(
                "tmuxPane.configUpdate failed pane=\(paneID) result=\(String(describing: result))"
            )
            return false
        }
        view.applyTerminalTheme(theme)
        managedSurface?.notifyLocalSelectionGeometryChanged()
        if !presented { lastPublishedViewportMetrics = nil }
        return true
    }

    func replaceRenderer(
        baseConfig: ghostty_terminal_surface_config_s,
        metrics: GhosttySurfaceDisplayMetrics,
        theme: TerminalTheme,
        completion: @escaping @MainActor (RendererReplacementResult) -> Void
    ) {
        guard lifecycle == .active else {
            completion(lifecycle == .replacing ? .busy : .failed)
            return
        }
        guard !presented else {
            assertionFailure("session must unpublish before renderer replacement")
            completion(.failed)
            return
        }
        lifecycle = .replacing
        publishedFrameObserver.invalidate()
        // This call is the single replacement attempt for the triggering
        // failure/settings change. Failures inside it return through
        // completion; they must not recursively schedule another attempt.
        rendererFailureReported = true
        cancelPresentationPreparation()
        lastPublishedViewportMetrics = nil

        let installReplacement = { [self] in
            guard lifecycle == .replacing else {
                finishCloseIfRendererless()
                completion(.failed)
                return
            }
            view.applyTerminalTheme(theme)
            view.frame.size = CGSize(
                width: Double(metrics.pixelWidth) / metrics.contentScale,
                height: Double(metrics.pixelHeight) / metrics.contentScale
            )
            view.contentScaleFactor = metrics.contentScale
            canonicalViewportMetrics = metrics
            appliedDisplayMetrics = metrics

            var config = Self.configured(
                baseConfig,
                view: view,
                metrics: metrics,
                callbackBox: callbackBox,
                visible: false,
                focused: false
            )
            var replacement: ghostty_terminal_surface_t?
            let result = ghostty_terminal_surface_new(
                app,
                terminal.handle,
                &config,
                &replacement
            )
            guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK, let replacement else {
                lifecycle = .active
                completion(.failed)
                return
            }
            view.alignGhosttyRendererSublayers()

            let wrapper = GhosttyKitControlSurface(
                surface: replacement,
                scaleFactor: metrics.contentScale,
                onFailure: { [weak failureRelay] _ in
                    failureRelay?.pane?.rendererDidFail()
                }
            )
            renderer = Renderer(handle: replacement, control: wrapper)
            controller.registerTerminalSurface(paneID: paneID, surface: replacement) { [self] result in
                guard case .success = result else {
                    wrapper.invalidate()
                    ghostty_terminal_surface_free(replacement)
                    renderer = nil
                    if lifecycle == .closing {
                        finishCloseIfRendererless()
                    } else {
                        lifecycle = .active
                    }
                    completion(.failed)
                    return
                }

                guard lifecycle != .closing else {
                    controller.unregisterTerminalSurface(
                        paneID: paneID,
                        surface: replacement
                    ) { [self] in
                        wrapper.invalidate()
                        ghostty_terminal_surface_free(replacement)
                        renderer = nil
                        finishCloseIfRendererless()
                        completion(.failed)
                    }
                    return
                }
                lifecycle = .active
                rendererFailureReported = false
                managedSurface?.replaceControlSurface(wrapper)
                installPublishedFrameInteractionObservation()
                completion(.replaced)
            }
        }

        guard let oldRenderer = renderer else {
            installReplacement()
            return
        }
        controller.unregisterTerminalSurface(
            paneID: paneID,
            surface: oldRenderer.handle
        ) { [self] in
            oldRenderer.control.invalidate()
            ghostty_terminal_surface_free(oldRenderer.handle)
            if renderer?.handle == oldRenderer.handle { renderer = nil }
            guard lifecycle != .closing else {
                finishCloseIfRendererless()
                completion(.failed)
                return
            }
            installReplacement()
        }
    }

    var isClosing: Bool { lifecycle == .closing || lifecycle == .closed }

    func close(completion: @escaping @MainActor @Sendable () -> Void = {}) {
        if lifecycle == .closed {
            completion()
            return
        }
        closeCompletions.append(completion)
        guard lifecycle != .closing else { return }
        let wasReplacing = lifecycle == .replacing
        lifecycle = .closing
        publishedFrameObserver.invalidate()
        cancelPresentationPreparation()
        frameRelay.pane = nil
        failureRelay.pane = nil
        managedSurface?.prepareForPermanentRemoval()
        guard !wasReplacing else { return }
        guard let renderer else {
            finishCloseIfRendererless()
            return
        }
        controller.unregisterTerminalSurface(
            paneID: paneID,
            surface: renderer.handle
        ) { [self] in
            renderer.control.invalidate()
            ghostty_terminal_surface_free(renderer.handle)
            if self.renderer?.handle == renderer.handle { self.renderer = nil }
            finishCloseIfRendererless()
        }
    }

    private func installPublishedFrameInteractionObservation() {
        guard lifecycle == .active,
              let managedSurface,
              let rendererLayer = GhosttyRendererLayer.find(in: view.layer)
        else { return }
        publishedFrameObserver.observe(rendererLayer, target: managedSurface)
    }

    private func rendererDidFail() {
        guard lifecycle == .active, !rendererFailureReported else { return }
        rendererFailureReported = true
        onRendererFailure(paneID)
    }

    private func applyPresentationActivity() {
        let active = presented && sceneActive
        if let managedSurface {
            managedSurface.setFocused(active)
            managedSurface.setVisible(active)
        } else {
            _ = renderer?.control.setFocused(active)
            _ = renderer?.control.setVisible(active)
        }
    }

    private func destroyUnregisteredRenderer() {
        lifecycle = .closed
        publishedFrameObserver.invalidate()
        cancelPresentationPreparation()
        frameRelay.pane = nil
        failureRelay.pane = nil
        renderer?.control.invalidate()
        if let renderer { ghostty_terminal_surface_free(renderer.handle) }
        renderer = nil
    }

    private func finishCloseIfRendererless() {
        guard lifecycle == .closing, renderer == nil else { return }
        lifecycle = .closed
        let completions = closeCompletions
        closeCompletions.removeAll()
        for completion in completions { completion() }
    }

    private static func configured(
        _ base: ghostty_terminal_surface_config_s,
        view: GhosttyKitSurfaceView,
        metrics: GhosttySurfaceDisplayMetrics,
        callbackBox: CallbackBox,
        visible: Bool,
        focused: Bool
    ) -> ghostty_terminal_surface_config_s {
        var config = base
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
            uiview: Unmanaged.passUnretained(view).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(callbackBox).toOpaque()
        config.renderer_health_cb = CallbackBox.healthCallback
        config.write_cb = CallbackBox.writeCallback
        config.scale_factor = metrics.contentScale
        config.width_px = metrics.pixelWidth
        config.height_px = metrics.pixelHeight
        config.visible = visible
        config.focused = focused
        return config
    }

    private func waitForViewportFrame(
        on layer: CALayer,
        expectedWidth: UInt32,
        expectedHeight: UInt32
    ) async -> Bool {
        // Resize is ordered before visibility. The next published IOSurface is
        // therefore the first frame safe to hand to the selected viewport.
        layer.displayIfNeeded()
        return await withCheckedContinuation { continuation in
            guard !Task.isCancelled, framePublicationWait == nil else {
                continuation.resume(returning: false)
                return
            }
            let wait = FramePublicationWait(
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight
            )
            let layerReference = LayerReference(layer)
            let relay = frameRelay
            wait.continuation = continuation
            framePublicationWait = wait
            wait.observation = layer.observe(\.contents, options: [.new]) { [weak wait] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let pane = relay.pane,
                              let wait,
                              let layer = layerReference.layer
                        else { return }
                        pane.finishFramePublicationIfMatching(wait, layer: layer)
                    }
                }
            }
            _ = renderer?.control.setFocused(true)
            guard renderer?.control.setVisible(true) == true else {
                finishFramePublicationWait(wait, didPublish: false)
                return
            }
        }
    }

    private func finishFramePublicationIfMatching(
        _ wait: FramePublicationWait,
        layer: CALayer
    ) {
        guard framePublicationWait === wait,
              let dimensions = GhosttyRendererLayer.dimensions(in: layer),
              dimensions.width == Int(wait.expectedWidth),
              dimensions.height == Int(wait.expectedHeight)
        else { return }
        finishFramePublicationWait(wait, didPublish: true)
    }

    private func finishFramePublicationWait(
        _ wait: FramePublicationWait,
        didPublish: Bool
    ) {
        guard framePublicationWait === wait else { return }
        wait.observation?.invalidate()
        wait.observation = nil
        framePublicationWait = nil
        if !didPublish, !presented {
            _ = renderer?.control.setVisible(false)
        }
        let continuation = wait.continuation
        wait.continuation = nil
        continuation?.resume(returning: didPublish)
    }

    private func cancelFramePublicationWait() {
        guard let wait = framePublicationWait else { return }
        finishFramePublicationWait(wait, didPublish: false)
    }

    private func hasCurrentViewportFrame() -> Bool {
        guard lastPublishedViewportMetrics == canonicalViewportMetrics,
              let layer = GhosttyRendererLayer.find(in: view.layer),
              let dimensions = GhosttyRendererLayer.dimensions(in: layer)
        else { return false }
        return dimensions.width == Int(canonicalViewportMetrics.pixelWidth)
            && dimensions.height == Int(canonicalViewportMetrics.pixelHeight)
    }

    private func applyDisplayMetrics(
        _ metrics: GhosttySurfaceDisplayMetrics
    ) -> Bool {
        guard let renderer,
              metrics.contentScale == canonicalViewportMetrics.contentScale
        else { return false }
        if metrics == appliedDisplayMetrics { return true }
        view.frame.size = CGSize(
            width: Double(metrics.pixelWidth) / metrics.contentScale,
            height: Double(metrics.pixelHeight) / metrics.contentScale
        )
        view.contentScaleFactor = metrics.contentScale
        view.alignGhosttyRendererSublayers()
        guard renderer.control.updateDisplay(metrics: metrics) else {
            return false
        }
        appliedDisplayMetrics = metrics
        return true
    }

    deinit {
        let finalLifecycle = lifecycle
        assert(finalLifecycle == .closed, "TmuxPaneSurface deinit without close()")
    }
}
