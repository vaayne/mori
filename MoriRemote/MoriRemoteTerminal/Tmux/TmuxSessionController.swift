import Foundation
import GhosttyKit

private func decodeTmuxString(_ bytes: ghostty_tmux_bytes_s) -> String {
    guard let pointer = bytes.ptr, bytes.len > 0 else { return "" }
    return String(
        decoding: UnsafeBufferPointer(start: pointer, count: bytes.len),
        as: UTF8.self
    )
}

/// Queue-confined host for Ghostty's sans-I/O tmux control client.
///
/// The SSH transport owns the wire. This type owns protocol parsing, copied
/// topology, command correlation, canonical pane-terminal handoff, and the
/// borrowed renderer handles used to notify retained pane surfaces directly.
/// Every libghostty call for one client runs on `queue`.
final class TmuxSessionController: @unchecked Sendable {
    enum SessionState: Equatable, Sendable {
        case detached(DetachReason?)
        case attaching
        case syncing
        case ready
        case closed(CloseReason)
    }

    enum DetachReason: Equatable, Sendable {
        case serverExited(String?)
        case channelAborted
        case outOfMemory
        case transportClosed
    }

    enum CloseReason: Equatable, Sendable {
        case unsupportedVersion(String)
    }

    struct WindowInfo: Equatable, Identifiable, Sendable {
        let id: TmuxWindowID
        let name: String
        let active: Bool
        let zoomed: Bool
        let width: UInt32
        let height: UInt32
        let activePaneID: TmuxPaneID?
    }

    struct PaneInfo: Equatable, Identifiable, Sendable {
        enum Phase: Equatable, Sendable {
            case hydrating
            case live
        }

        let id: TmuxPaneID
        let windowID: TmuxWindowID
        let x: UInt32
        let y: UInt32
        let width: UInt32
        let height: UInt32
        let phase: Phase
    }

    struct TopologySnapshot: Equatable, Sendable {
        let sessionName: String
        let windows: [WindowInfo]
        let panes: [PaneInfo]
        let activeWindowID: TmuxWindowID?
    }

    enum Request: Equatable, Sendable {
        case selectWindow
        case selectPane
        case sharedMutation
        case sendInput
        case setClientSize
    }

    enum SharedMutation: Sendable {
        case newWindow
        case splitHorizontal
        case splitVertical
        case closePane
        case closeWindow
    }

    struct ClientSize: Sendable, Equatable {
        let cols: UInt32
        let rows: UInt32

        var controlViewport: TmuxControlViewport? {
            guard let columns = UInt16(exactly: cols),
                  let rows = UInt16(exactly: rows),
                  columns > 0,
                  rows > 0
            else { return nil }
            return TmuxControlViewport(
                columns: columns,
                rows: rows,
                pixelWidth: 0,
                pixelHeight: 0
            )
        }
    }

    enum StartError: Error {
        case invalidInitialGrid
        case alreadyStarted
        case creationFailed(ghostty_tmux_result_e)
    }

    enum SurfaceRegistrationError: Error {
        case clientUnavailable
        case paneUnknown
        case alreadyRegistered
    }

    struct AgentMetadataQueryResult: Sendable {
        enum Status: Sendable { case success, skipped, failed }
        let status: Status
        let body: String
    }

    /// One retained reference to ControlClient's canonical pane terminal.
    /// Ownership transfers from the writer queue to MainActor exactly once.
    final class RetainedPaneTerminal: @unchecked Sendable {
        let paneID: TmuxPaneID
        let handle: ghostty_terminal_t

        fileprivate init(paneID: TmuxPaneID, handle: ghostty_terminal_t) {
            self.paneID = paneID
            self.handle = handle
        }

        deinit {
            ghostty_terminal_release(handle)
        }
    }

    struct Callbacks: Sendable {
        var onState: @Sendable (SessionState) -> Void = { _ in }
        var onTopology: @Sendable (TopologySnapshot) -> Void = { _ in }
        var onPaneRemoved: @Sendable (TmuxPaneID) -> Void = { _ in }
        var onPaneTerminal: @Sendable (RetainedPaneTerminal) -> Void = { _ in }
        var onPanePhaseChanged: @Sendable (TmuxPaneID, PaneInfo.Phase) -> Void = { _, _ in }
        var onActivePaneChanged: @Sendable (TmuxPaneID) -> Void = { _ in }
        var onPaneSurfaceFailed: @Sendable (TmuxPaneID) -> Void = { _ in }
        var onRequestFailed: @Sendable (Request) -> Void = { _ in }
    }

    /// Pointer values cross actor boundaries only as opaque native identities.
    private struct TerminalSurfaceHandle: @unchecked Sendable, Equatable {
        let value: ghostty_terminal_surface_t

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.value == rhs.value
        }
    }

    private enum NavigationIntent: Equatable {
        case pane(TmuxPaneID)
        case window(TmuxWindowID, preferredPaneID: TmuxPaneID?)
    }

    private enum OutstandingRequest {
        case action(Request, topologyRevisionAtSubmission: UInt64)
        case agentMetadata(@Sendable (AgentMetadataQueryResult) -> Void)
    }

    private struct DesiredPaneRefresh {
        let size: ClientSize
        let failureRequest: Request
        let requiredAfterPresentation: Bool
    }

    private enum PaneRefreshState {
        case deferred(DesiredPaneRefresh)
        case inFlight(size: ClientSize, followUp: DesiredPaneRefresh?)
    }

    let queue: DispatchQueue

    private let callbacks: Callbacks
    private var client: ghostty_tmux_client_t?
    private var state: SessionState = .detached(nil)
    private var topology: TopologySnapshot?
    private var retainedPaneIDs: Set<TmuxPaneID> = []
    private var engineSizeByPaneID: [TmuxPaneID: ClientSize] = [:]
    private var refreshStateByPaneID: [TmuxPaneID: PaneRefreshState] = [:]
    private var surfacesByPaneID: [TmuxPaneID: TerminalSurfaceHandle] = [:]
    private var requestsByToken: [UInt64: OutstandingRequest] = [:]
    private var deferredNavigationIntent: NavigationIntent?
    private var successfulMutationRequiredAfterRevision: UInt64?
    private var topologyRevision: UInt64 = 0
    private var outboundSink: (@Sendable (Data) -> Void)?
    private var clientSize: ClientSize?
    private var shuttingDown = false
    private let historyLineLimit: Int

    init(
        historyLineLimit: Int = 2_000,
        callbacks: Callbacks,
        queue: DispatchQueue = DispatchQueue(label: "remux.tmux.session.writer")
    ) {
        self.historyLineLimit = max(2_000, min(historyLineLimit, 10_000))
        self.callbacks = callbacks
        self.queue = queue
    }

    deinit {
        assert(client == nil, "TmuxSessionController deinit without shutdown()")
    }

    func setOutboundSink(_ sink: (@Sendable (Data) -> Void)?) {
        queue.async { [self] in
            outboundSink = sink
        }
    }

    /// Construct the native client only after transport.start has opened the
    /// grouped shadow control channel with this same real client grid.
    func start(
        initialSize: ClientSize,
        completion: @escaping @Sendable (Result<Void, StartError>) -> Void
    ) {
        queue.async { [self] in
            guard client == nil, !shuttingDown else {
                completion(.failure(.alreadyStarted))
                return
            }

            guard let columns = UInt16(exactly: initialSize.cols),
                  let rows = UInt16(exactly: initialSize.rows),
                  columns > 0,
                  rows > 0 else {
                completion(.failure(.invalidInitialGrid))
                return
            }
            clientSize = initialSize

            var config = ghostty_tmux_client_config_new()
            config.userdata = Unmanaged.passUnretained(self).toOpaque()
            config.action_cb = { userdata, action in
                guard let userdata, let action else { return }
                let controller = Unmanaged<TmuxSessionController>
                    .fromOpaque(userdata).takeUnretainedValue()
                controller.handleAction(action.pointee)
            }
            config.history_line_limit_is_set = true
            config.history_line_limit = self.historyLineLimit
            config.max_scrollback = 10_000
            config.initial_columns = columns
            config.initial_rows = rows

            var created: ghostty_tmux_client_t?
            let result = ghostty_tmux_client_new(&config, &created)
            guard result == GHOSTTY_TMUX_RESULT_OK, let created else {
                completion(.failure(.creationFailed(result)))
                return
            }
            client = created
            publishState(.attaching)
            completion(.success(()))
        }
    }

    func transportClosed() {
        queue.async { [self] in
            guard !shuttingDown else { return }
            failOutstandingAgentMetadataQueries()
            deferredNavigationIntent = nil
            successfulMutationRequiredAfterRevision = nil
            guard case .closed = state else {
                publishState(.detached(.transportClosed))
                return
            }
        }
    }

    /// Publish an intentional attachment stop without classifying it as a
    /// transport failure. Link teardown itself stays silent because it is
    /// also used by startup-failure cleanup and session shutdown.
    func attachmentStopped() {
        queue.async { [self] in
            guard !shuttingDown else { return }
            failOutstandingAgentMetadataQueries()
            deferredNavigationIntent = nil
            successfulMutationRequiredAfterRevision = nil
            guard case .closed = state else {
                publishState(.detached(nil))
                return
            }
        }
    }

    func shutdown(completion: @escaping @Sendable () -> Void = {}) {
        queue.async { [self] in
            shuttingDown = true
            outboundSink = nil
            let agentMetadataQueries = outstandingAgentMetadataQueries()
            requestsByToken.removeAll()
            agentMetadataQueries.forEach { $0(.init(status: .failed, body: "")) }
            deferredNavigationIntent = nil
            successfulMutationRequiredAfterRevision = nil
            topology = nil
            clientSize = nil
            retainedPaneIDs.removeAll()
            engineSizeByPaneID.removeAll()
            refreshStateByPaneID.removeAll()
            assert(surfacesByPaneID.isEmpty, "terminal surfaces must unregister before client free")
            surfacesByPaneID.removeAll()
            if let client {
                let result = ghostty_tmux_client_free(client)
                assert(result == GHOSTTY_TMUX_RESULT_OK, "ghostty_tmux_client_free failed: \(result)")
            }
            client = nil
            DispatchQueue.main.async(execute: completion)
        }
    }

    func pump(_ data: Data) {
        let enqueuedAt = GhosttyRuntimeTrace.perfEnabled ? GhosttyRuntimeTrace.nowNanos() : 0
        queue.async { [self, data] in
            guard let client, !shuttingDown else { return }
            let applyStart = GhosttyRuntimeTrace.perfEnabled ? GhosttyRuntimeTrace.nowNanos() : 0
            let result = data.withUnsafeBytes { bytes in
                ghostty_tmux_client_feed(
                    client,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    bytes.count
                )
            }
            if state == .attaching {
                publishState(.syncing)
            }
            let outboundBytes = drainOutbound()
            GhosttyRuntimeTrace.perf(
                "tmuxFeed bytes=\(data.count) wait_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: enqueuedAt, to: applyStart)) apply_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: applyStart)) outbound_bytes=\(outboundBytes) result=\(result)"
            )
            guard result == GHOSTTY_TMUX_RESULT_OK else {
                handleClientFailure(result)
                return
            }
        }
    }

    @discardableResult
    private func drainOutbound() -> Int {
        preconditionOnWriterQueue()
        guard let client else { return 0 }
        var bytes = ghostty_tmux_bytes_s()
        let result = ghostty_tmux_client_outbound(client, &bytes)
        guard result == GHOSTTY_TMUX_RESULT_OK else {
            handleClientFailure(result)
            return 0
        }
        guard bytes.len > 0 else { return 0 }
        guard let pointer = bytes.ptr else {
            handleClientFailure(GHOSTTY_TMUX_RESULT_CLIENT_FAILED)
            return 0
        }

        let owned = Data(bytes: pointer, count: bytes.len)
        let consumeResult = ghostty_tmux_client_consume(client, bytes.len)
        guard consumeResult == GHOSTTY_TMUX_RESULT_OK else {
            handleClientFailure(consumeResult)
            return 0
        }
        outboundSink?(owned)
        return owned.count
    }

    // MARK: Native actions

    private func handleAction(_ action: ghostty_tmux_action_s) {
        preconditionOnWriterQueue()
        switch action.tag {
        case GHOSTTY_TMUX_ACTION_EXIT:
            failOutstandingAgentMetadataQueries()
            deferredNavigationIntent = nil
            successfulMutationRequiredAfterRevision = nil
            let exit = action.value.exit
            let detail = decodeTmuxString(exit.detail)
            switch exit.reason {
            case GHOSTTY_TMUX_EXIT_UNSUPPORTED_VERSION:
                publishState(.closed(.unsupportedVersion(detail)))
            case GHOSTTY_TMUX_EXIT_SERVER:
                publishState(.detached(.serverExited(detail.isEmpty ? nil : detail)))
            default:
                publishState(.detached(.channelAborted))
            }

        case GHOSTTY_TMUX_ACTION_TOPOLOGY:
            handleTopology(action.value.topology)

        case GHOSTTY_TMUX_ACTION_PANE_CHANGED:
            handlePaneChanged(TmuxPaneID(action.value.pane_id))

        case GHOSTTY_TMUX_ACTION_COMMAND_COMPLETE:
            handleCommandCompletion(action.value.command)

        case GHOSTTY_TMUX_ACTION_INPUT_FAILED:
            _ = decodeTmuxString(action.value.input_failure)
            DispatchQueue.main.async { self.callbacks.onRequestFailed(.sendInput) }

        default:
            handleClientFailure(GHOSTTY_TMUX_RESULT_CLIENT_FAILED)
        }
    }

    private func handleTopology(_ action: ghostty_tmux_topology_action_s) {
        preconditionOnWriterQueue()
        var accumulator = TopologyAccumulator()
        let visitResult = withUnsafeMutablePointer(to: &accumulator) { accumulator in
            ghostty_tmux_topology_visit(
                action.view,
                UnsafeMutableRawPointer(accumulator),
                { userdata, record in
                    guard let userdata, let record else { return }
                    userdata.assumingMemoryBound(to: TopologyAccumulator.self)
                        .pointee.append(record.pointee)
                }
            )
        }
        guard visitResult == GHOSTTY_TMUX_RESULT_OK else {
            handleClientFailure(visitResult)
            return
        }

        let snapshot = TopologySnapshot(
            sessionName: decodeTmuxString(action.session_name),
            windows: accumulator.windows,
            panes: accumulator.panes,
            activeWindowID: accumulator.windows.first(where: \.active)?.id
        )
        let previousPaneIDs = Set(topology?.panes.map(\.id) ?? [])
        let nextPaneIDs = Set(snapshot.panes.map(\.id))
        let removed = previousPaneIDs.subtracting(nextPaneIDs).sorted()
        for pane in snapshot.panes where refreshStateByPaneID[pane.id] == nil {
            // Topology resizes each non-refreshing canonical terminal to its
            // effective tmux grid. A refresh owns its target grid until its
            // deterministic PANE_CHANGED completion.
            if let size = Self.effectiveEngineSize(for: pane, in: snapshot) {
                engineSizeByPaneID[pane.id] = size
            } else {
                engineSizeByPaneID.removeValue(forKey: pane.id)
            }
        }
        topology = snapshot
        topologyRevision &+= 1
        clearSatisfiedMutationBarrier()

        for paneID in removed {
            retainedPaneIDs.remove(paneID)
            engineSizeByPaneID.removeValue(forKey: paneID)
            refreshStateByPaneID.removeValue(forKey: paneID)
            surfacesByPaneID.removeValue(forKey: paneID)
        }
        let didBecomeReady = state != .ready
        state = .ready
        DispatchQueue.main.async {
            if didBecomeReady { self.callbacks.onState(.ready) }
            for paneID in removed { self.callbacks.onPaneRemoved(paneID) }
            self.callbacks.onTopology(snapshot)
        }
        admitDeferredNavigationIfPossible()
    }

    private func handlePaneChanged(_ paneID: TmuxPaneID) {
        preconditionOnWriterQueue()
        guard let client else { return }

        let completedRefresh: (size: ClientSize, followUp: DesiredPaneRefresh?)?
        if case .inFlight(let size, let followUp) = refreshStateByPaneID[paneID] {
            completedRefresh = (size, followUp)
            if let topology,
               let pane = topology.panes.first(where: { $0.id == paneID }),
               let actualSize = Self.effectiveEngineSize(for: pane, in: topology) {
                engineSizeByPaneID[paneID] = actualSize
            } else {
                engineSizeByPaneID.removeValue(forKey: paneID)
            }
            refreshStateByPaneID.removeValue(forKey: paneID)
        } else {
            completedRefresh = nil
        }

        if retainedPaneIDs.insert(paneID).inserted {
            var terminal: ghostty_terminal_t?
            let result = ghostty_tmux_client_retain_pane_terminal(
                client,
                paneID.rawValue,
                &terminal
            )
            guard result == GHOSTTY_TMUX_RESULT_OK, let terminal else {
                retainedPaneIDs.remove(paneID)
                DispatchQueue.main.async { self.callbacks.onPaneSurfaceFailed(paneID) }
                return
            }
            let handoff = RetainedPaneTerminal(paneID: paneID, handle: terminal)
            DispatchQueue.main.async { self.callbacks.onPaneTerminal(handoff) }
            retryDeferredPaneRefreshIfNeeded(paneID, notifyPhaseChange: true)
            return
        }

        if let surface = surfacesByPaneID[paneID] {
            let result = ghostty_terminal_surface_terminal_changed(surface.value)
            if result != GHOSTTY_TERMINAL_SURFACE_RESULT_OK {
                surfacesByPaneID.removeValue(forKey: paneID)
                DispatchQueue.main.async { self.callbacks.onPaneSurfaceFailed(paneID) }
                return
            }
        }

        if let completedRefresh {
            if let followUp = completedRefresh.followUp {
                refreshStateByPaneID[paneID] = .deferred(followUp)
                retryDeferredPaneRefreshIfNeeded(paneID, notifyPhaseChange: false)
            }
            guard refreshStateByPaneID[paneID] != nil else {
                DispatchQueue.main.async {
                    self.callbacks.onPanePhaseChanged(paneID, .live)
                }
                if activePaneID(in: topology) == paneID {
                    DispatchQueue.main.async { self.callbacks.onActivePaneChanged(paneID) }
                }
                return
            }
            return
        }

        if activePaneID(in: topology) == paneID {
            DispatchQueue.main.async { self.callbacks.onActivePaneChanged(paneID) }
        }
    }

    private func handleCommandCompletion(_ completion: ghostty_tmux_command_completion_s) {
        preconditionOnWriterQueue()
        guard let outstanding = requestsByToken.removeValue(forKey: completion.token) else { return }
        switch outstanding {
        case .agentMetadata(let completionHandler):
            let status: AgentMetadataQueryResult.Status = switch completion.status {
            case GHOSTTY_TMUX_COMMAND_SUCCESS: .success
            case GHOSTTY_TMUX_COMMAND_SKIPPED: .skipped
            default: .failed
            }
            completionHandler(.init(status: status, body: decodeTmuxString(completion.body)))
            return
        case .action(let request, let topologyRevisionAtSubmission):
            handleActionCompletion(
                completion,
                request: request,
                topologyRevisionAtSubmission: topologyRevisionAtSubmission
            )
        }
    }

    private func handleActionCompletion(
        _ completion: ghostty_tmux_command_completion_s,
        request: Request,
        topologyRevisionAtSubmission: UInt64
    ) {
        preconditionOnWriterQueue()
        switch completion.status {
        case GHOSTTY_TMUX_COMMAND_SUCCESS:
            if requestMutatesTopology(request) {
                successfulMutationRequiredAfterRevision = max(
                    successfulMutationRequiredAfterRevision ?? 0,
                    topologyRevisionAtSubmission
                )
            }
        case GHOSTTY_TMUX_COMMAND_SKIPPED:
            break
        case GHOSTTY_TMUX_COMMAND_ERROR_BLOCK:
            _ = decodeTmuxString(completion.body)
            DispatchQueue.main.async { self.callbacks.onRequestFailed(request) }
        default:
            DispatchQueue.main.async { self.callbacks.onRequestFailed(request) }
        }
        clearSatisfiedMutationBarrier()
        admitDeferredNavigationIfPossible()
    }

    // MARK: Renderer registration and lifetime fence

    func registerTerminalSurface(
        paneID: TmuxPaneID,
        surface: ghostty_terminal_surface_t,
        completion: @escaping @MainActor @Sendable (Result<Void, SurfaceRegistrationError>) -> Void
    ) {
        let handle = TerminalSurfaceHandle(value: surface)
        queue.async { [self, handle] in
            let result: Result<Void, SurfaceRegistrationError>
            if client == nil || shuttingDown {
                result = .failure(.clientUnavailable)
            } else if !retainedPaneIDs.contains(paneID) {
                result = .failure(.paneUnknown)
            } else if surfacesByPaneID[paneID] != nil {
                result = .failure(.alreadyRegistered)
            } else {
                surfacesByPaneID[paneID] = handle
                result = .success(())
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    /// Completion is the happens-before fence: every earlier terminal-change
    /// notification has returned and no later one can dereference the handle.
    func unregisterTerminalSurface(
        paneID: TmuxPaneID,
        surface: ghostty_terminal_surface_t,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let handle = TerminalSurfaceHandle(value: surface)
        queue.async { [self, handle] in
            if surfacesByPaneID[paneID] == handle {
                surfacesByPaneID.removeValue(forKey: paneID)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion() }
            }
        }
    }

    // MARK: Input and commands

    /// Runs immediately before input on Mori's grouped shadow client. It only
    /// leaves a stale server copy mode; renderer-local selection and scrolling
    /// never issue this command.
    static let cancelStaleSharedInputMode = "if-shell -F '#{pane_in_mode}' 'send-keys -X cancel' ''"
    // tmux 3.2's `q` modifier escapes separators and backslashes. Filter out
    // control characters first because that version cannot encode them; this
    // keeps every emitted pane on exactly one line without raising our minimum.
    static let agentMetadataQuery = "list-panes -a -f '#{&&:#{==:#{m/r:[[:cntrl:]],#{session_name}},0},#{&&:#{==:#{m/r:[[:cntrl:]],#{window_name}},0},#{&&:#{==:#{m/r:[[:cntrl:]],#{@mori-agent-state}},0},#{==:#{m/r:[[:cntrl:]],#{@mori-agent-name}},0}}}}' -F '#{q:session_name}|#{window_id}|#{q:window_name}|#{pane_id}|#{q:@mori-agent-state}|#{q:@mori-agent-name}'"

    func sendInput(paneID: TmuxPaneID, _ bytes: Data) -> Bool {
        guard !bytes.isEmpty else { return true }
        queue.async { [self, bytes] in
            guard let client, !shuttingDown else {
                DispatchQueue.main.async { self.callbacks.onRequestFailed(.sendInput) }
                return
            }
            guard admitCommandOnWriter(
                command: Self.cancelStaleSharedInputMode,
                request: .sendInput
            ) else { return }
            let result = bytes.withUnsafeBytes { buffer in
                ghostty_tmux_client_send_pane_input(
                    client,
                    paneID.rawValue,
                    buffer.bindMemory(to: UInt8.self).baseAddress,
                    buffer.count
                )
            }
            if result == GHOSTTY_TMUX_RESULT_OK {
                _ = drainOutbound()
            } else {
                reportImmediateFailure(result, request: .sendInput)
            }
        }
        return true
    }

    func setClientSize(cols: UInt32, rows: UInt32) {
        guard cols > 0, rows > 0, cols <= UInt16.max, rows <= UInt16.max else {
            DispatchQueue.main.async { self.callbacks.onRequestFailed(.setClientSize) }
            return
        }
        let nextSize = ClientSize(cols: cols, rows: rows)
        queue.async { [self] in
            guard clientSize != nextSize else { return }
            guard admitCommandOnWriter(
                command: "refresh-client -C \(cols)x\(rows)",
                request: .setClientSize
            ) else { return }
            clientSize = nextSize
            if let paneID = activePaneID(in: topology) {
                _ = admitPaneRefreshIfNeeded(paneID, failureRequest: .setClientSize)
            }
            _ = drainOutbound()
        }
    }

    /// Selectors target Mori's grouped shadow client only; they never resize
    /// panes, toggle zoom, or mutate shared layout.
    func requestSelectWindow(
        windowID: TmuxWindowID,
        preferredPaneID: TmuxPaneID? = nil
    ) {
        queue.async { [self] in
            submitNavigation(.window(windowID, preferredPaneID: preferredPaneID))
        }
    }

    func requestSelectPane(paneID: TmuxPaneID) {
        queue.async { [self] in submitNavigation(.pane(paneID)) }
    }

    /// Explicit, user-labelled shared mutations only. Navigation and renderer
    /// gestures do not reach this API.
    func requestSharedMutation(_ mutation: SharedMutation) {
        queue.async { [self] in
            guard let topology, let activeWindow = topology.activeWindowID else {
                reportRequestFailure(.sharedMutation); return
            }
            let activePane = activePaneID(in: topology)
            let command: String?
            switch mutation {
            case .newWindow: command = "new-window"
            case .splitHorizontal: command = activePane.map { "split-window -h -t %\($0.rawValue)" }
            case .splitVertical: command = activePane.map { "split-window -v -t %\($0.rawValue)" }
            case .closePane: command = activePane.map { "kill-pane -t %\($0.rawValue)" }
            case .closeWindow: command = "kill-window -t @\(activeWindow.rawValue)"
            }
            guard let command else { reportRequestFailure(.sharedMutation); return }
            enqueueOnWriter(command: command, request: .sharedMutation)
        }
    }

    /// The sole app-domain query admitted by the terminal boundary. The
    /// format is fixed; callers cannot inject arbitrary tmux commands.
    func queryAgentMetadata(completion: @escaping @Sendable (AgentMetadataQueryResult) -> Void) {
        queue.async { [self] in
            guard let client, !shuttingDown else { completion(.init(status: .failed, body: "")); return }
            let (result, token) = enqueueCommandTokenOnWriter(Self.agentMetadataQuery, client: client)
            guard result == GHOSTTY_TMUX_RESULT_OK else { completion(.init(status: .failed, body: "")); return }
            requestsByToken[token] = .agentMetadata(completion)
            _ = drainOutbound()
        }
    }

    private func submitNavigation(_ intent: NavigationIntent) {
        preconditionOnWriterQueue()
        guard !navigationAdmissionBlocked else {
            deferredNavigationIntent = intent
            return
        }
        deferredNavigationIntent = nil
        evaluateNavigation(intent, drainOutbound: true)
    }

    private func clearSatisfiedMutationBarrier() {
        preconditionOnWriterQueue()
        guard let requiredRevision = successfulMutationRequiredAfterRevision,
              topologyRevision > requiredRevision
        else { return }
        successfulMutationRequiredAfterRevision = nil
    }

    private func admitDeferredNavigationIfPossible() {
        preconditionOnWriterQueue()
        guard !navigationAdmissionBlocked,
              let deferredNavigationIntent
        else { return }
        self.deferredNavigationIntent = nil
        // Native command admission is callback-safe. Outbound consume is not;
        // the enclosing pump drains once after feed returns.
        evaluateNavigation(deferredNavigationIntent, drainOutbound: false)
    }

    private func evaluateNavigation(
        _ intent: NavigationIntent,
        drainOutbound: Bool
    ) {
        switch intent {
        case .pane(let paneID):
            enqueuePaneSelection(paneID, drainOutbound: drainOutbound)
        case .window(let windowID, let preferredPaneID):
            enqueueWindowSelection(
                windowID: windowID,
                preferredPaneID: preferredPaneID,
                drainOutbound: drainOutbound
            )
        }
    }

    /// Navigation is local to Mori's grouped shadow client. It must never
    /// alter server layout/zoom or client dimensions.
    private func enqueuePaneSelection(_ paneID: TmuxPaneID, drainOutbound: Bool) {
        guard let topology,
              let pane = topology.panes.first(where: { $0.id == paneID })
        else { reportRequestFailure(.selectPane); return }
        if topology.activeWindowID != pane.windowID {
            enqueueWindowSelection(windowID: pane.windowID, preferredPaneID: paneID, drainOutbound: drainOutbound)
            return
        }
        submitPanePresentationCommandOnWriter(
            command: "select-pane -t %\(paneID.rawValue)",
            request: .selectPane,
            paneID: paneID,
            drainOutbound: drainOutbound
        )
    }

    private func enqueueWindowSelection(
        windowID: TmuxWindowID,
        preferredPaneID: TmuxPaneID?,
        drainOutbound: Bool
    ) {
        guard let topology,
              let window = topology.windows.first(where: { $0.id == windowID })
        else { reportRequestFailure(.selectWindow); return }
        if let preferredPaneID,
           !topology.panes.contains(where: { $0.id == preferredPaneID && $0.windowID == windowID }) {
            reportRequestFailure(.selectWindow); return
        }
        let paneID = preferredPaneID ?? window.activePaneID
        let commands = ["select-window -t @\(windowID.rawValue)"]
            + (preferredPaneID.map { ["select-pane -t %\($0.rawValue)"] } ?? [])
        guard let paneID else {
            submitCommandOnWriter(command: commands[0], request: .selectWindow, drainOutbound: drainOutbound)
            return
        }
        submitPanePresentationCommandGroupOnWriter(
            commands: commands,
            request: .selectWindow,
            paneID: paneID,
            drainOutbound: drainOutbound
        )
    }

    private var hasOutstandingTopologyMutation: Bool {
        requestsByToken.values.contains {
            guard case .action(let request, _) = $0 else { return false }
            return requestMutatesTopology(request)
        }
    }

    private var navigationAdmissionBlocked: Bool {
        hasOutstandingTopologyMutation
            || successfulMutationRequiredAfterRevision != nil
    }

    private func requestMutatesTopology(_ request: Request) -> Bool {
        switch request {
        case .selectWindow, .selectPane, .sharedMutation:
            true
        case .sendInput, .setClientSize:
            false
        }
    }

    private func enqueue(command: String, request: Request) {
        queue.async { [self] in
            enqueueOnWriter(command: command, request: request)
        }
    }

    private func enqueueOnWriter(command: String, request: Request) {
        submitCommandOnWriter(
            command: command,
            request: request,
            drainOutbound: true
        )
    }

    private func submitCommandOnWriter(
        command: String,
        request: Request,
        drainOutbound: Bool
    ) {
        guard admitCommandOnWriter(command: command, request: request) else { return }
        if drainOutbound { _ = self.drainOutbound() }
    }

    private func submitPanePresentationCommandOnWriter(
        command: String,
        request: Request,
        paneID: TmuxPaneID,
        drainOutbound: Bool
    ) {
        guard admitCommandOnWriter(command: command, request: request) else { return }
        _ = admitPaneRefreshIfNeeded(
            paneID,
            failureRequest: request,
            followsPresentation: true
        )
        if drainOutbound { _ = self.drainOutbound() }
    }

    private func admitCommandOnWriter(command: String, request: Request) -> Bool {
        preconditionOnWriterQueue()
        guard let client, !shuttingDown else {
            reportRequestFailure(request)
            return false
        }
        let (result, token) = enqueueCommandTokenOnWriter(command, client: client)
        guard result == GHOSTTY_TMUX_RESULT_OK else {
            reportImmediateFailure(result, request: request)
            return false
        }
        requestsByToken[token] = .action(
            request,
            topologyRevisionAtSubmission: topologyRevision
        )
        return true
    }

    private func enqueueCommandTokenOnWriter(
        _ command: String,
        client: ghostty_tmux_client_t
    ) -> (ghostty_tmux_result_e, UInt64) {
        preconditionOnWriterQueue()
        var token: UInt64 = 0
        let result = command.utf8.withContiguousStorageIfAvailable { buffer in
            ghostty_tmux_client_enqueue_command(
                client,
                ghostty_tmux_bytes_s(ptr: buffer.baseAddress, len: buffer.count),
                &token
            )
        } ?? Array(command.utf8).withUnsafeBufferPointer { buffer in
            ghostty_tmux_client_enqueue_command(
                client,
                ghostty_tmux_bytes_s(ptr: buffer.baseAddress, len: buffer.count),
                &token
            )
        }
        return (result, token)
    }

    private func enqueueGroupOnWriter(commands: [String], request: Request) {
        submitCommandGroupOnWriter(
            commands: commands,
            request: request,
            drainOutbound: true
        )
    }

    private func submitCommandGroupOnWriter(
        commands: [String],
        request: Request,
        drainOutbound: Bool
    ) {
        guard admitCommandGroupOnWriter(commands: commands, request: request) else { return }
        if drainOutbound { _ = self.drainOutbound() }
    }

    private func submitPanePresentationCommandGroupOnWriter(
        commands: [String],
        request: Request,
        paneID: TmuxPaneID,
        drainOutbound: Bool
    ) {
        guard admitCommandGroupOnWriter(commands: commands, request: request) else { return }
        _ = admitPaneRefreshIfNeeded(
            paneID,
            failureRequest: request,
            followsPresentation: true
        )
        if drainOutbound { _ = self.drainOutbound() }
    }

    private func admitCommandGroupOnWriter(commands: [String], request: Request) -> Bool {
        preconditionOnWriterQueue()
        guard let client, !shuttingDown else {
            reportRequestFailure(request)
            return false
        }
        let encoded = commands.map { Array($0.utf8) }
        var tokens = Array(repeating: UInt64(0), count: commands.count)
        let result = withBorrowedCommandBytes(encoded, index: 0, bytes: []) { bytes in
            bytes.withUnsafeBufferPointer { commandBuffer in
                tokens.withUnsafeMutableBufferPointer { tokenBuffer in
                    ghostty_tmux_client_enqueue_command_group(
                        client,
                        commandBuffer.baseAddress,
                        commandBuffer.count,
                        tokenBuffer.baseAddress
                    )
                }
            }
        }
        guard result == GHOSTTY_TMUX_RESULT_OK else {
            reportImmediateFailure(result, request: request)
            return false
        }
        for token in tokens {
            requestsByToken[token] = .action(
                request,
                topologyRevisionAtSubmission: topologyRevision
            )
        }
        return true
    }

    private func withBorrowedCommandBytes<Result>(
        _ commands: [[UInt8]],
        index: Int,
        bytes: [ghostty_tmux_bytes_s],
        body: ([ghostty_tmux_bytes_s]) -> Result
    ) -> Result {
        guard index < commands.count else { return body(bytes) }
        return commands[index].withUnsafeBufferPointer { buffer in
            withBorrowedCommandBytes(
                commands,
                index: index + 1,
                bytes: bytes + [ghostty_tmux_bytes_s(ptr: buffer.baseAddress, len: buffer.count)],
                body: body
            )
        }
    }

    @discardableResult
    private func admitPaneRefreshIfNeeded(
        _ paneID: TmuxPaneID,
        failureRequest: Request,
        notifyPhaseChange: Bool = true,
        followsPresentation: Bool = false
    ) -> Bool {
        preconditionOnWriterQueue()
        guard let topology,
              let pane = topology.panes.first(where: { $0.id == paneID }),
              let size = Self.effectiveEngineSize(for: pane, in: topology)
        else { return false }
        let desired = DesiredPaneRefresh(
            size: size,
            failureRequest: failureRequest,
            requiredAfterPresentation: followsPresentation
        )

        if case .inFlight(let inFlightSize, let existingFollowUp) =
            refreshStateByPaneID[paneID] {
            let requiredAfterPresentation = followsPresentation
                || existingFollowUp?.requiredAfterPresentation == true
            refreshStateByPaneID[paneID] = .inFlight(
                size: inFlightSize,
                followUp: requiredAfterPresentation || size != inFlightSize
                    ? DesiredPaneRefresh(
                        size: size,
                        failureRequest: failureRequest,
                        requiredAfterPresentation: requiredAfterPresentation
                    )
                    : nil
            )
            return false
        }

        if engineSizeByPaneID[paneID] == size {
            refreshStateByPaneID.removeValue(forKey: paneID)
            return false
        }

        if case .deferred = refreshStateByPaneID[paneID] {
            refreshStateByPaneID[paneID] = .deferred(desired)
            return false
        }

        guard let client, !shuttingDown else {
            reportRequestFailure(failureRequest)
            return false
        }
        let result = ghostty_tmux_client_refresh_pane(client, paneID.rawValue)
        switch result {
        case GHOSTTY_TMUX_RESULT_OK:
            refreshStateByPaneID[paneID] = .inFlight(size: size, followUp: nil)
            if notifyPhaseChange {
                DispatchQueue.main.async {
                    self.callbacks.onPanePhaseChanged(paneID, .hydrating)
                }
            }
            return true
        case GHOSTTY_TMUX_RESULT_NOT_READY:
            refreshStateByPaneID[paneID] = .deferred(desired)
            return false
        default:
            reportImmediateFailure(result, request: failureRequest)
            return false
        }
    }

    private func retryDeferredPaneRefreshIfNeeded(
        _ paneID: TmuxPaneID,
        notifyPhaseChange: Bool
    ) {
        preconditionOnWriterQueue()
        guard case .deferred(let desired) = refreshStateByPaneID[paneID] else { return }
        refreshStateByPaneID.removeValue(forKey: paneID)
        _ = admitPaneRefreshIfNeeded(
            paneID,
            failureRequest: desired.failureRequest,
            notifyPhaseChange: notifyPhaseChange,
            followsPresentation: desired.requiredAfterPresentation
        )
    }

    // MARK: Helpers

    static func effectiveEngineSize(
        for pane: PaneInfo,
        in topology: TopologySnapshot
    ) -> ClientSize? {
        guard let window = topology.windows.first(where: { $0.id == pane.windowID })
        else { return nil }
        if window.zoomed, window.activePaneID == pane.id {
            return ClientSize(cols: window.width, rows: window.height)
        }
        return ClientSize(cols: pane.width, rows: pane.height)
    }

    private func publishState(_ next: SessionState) {
        preconditionOnWriterQueue()
        guard state != next else { return }
        state = next
        DispatchQueue.main.async { self.callbacks.onState(next) }
    }

    private func handleClientFailure(_ result: ghostty_tmux_result_e) {
        preconditionOnWriterQueue()
        guard !shuttingDown else { return }
        failOutstandingAgentMetadataQueries()
        deferredNavigationIntent = nil
        successfulMutationRequiredAfterRevision = nil
        switch result {
        case GHOSTTY_TMUX_RESULT_OUT_OF_MEMORY:
            publishState(.detached(.outOfMemory))
        case GHOSTTY_TMUX_RESULT_CLOSED:
            if case .closed = state { return }
            if case .detached = state { return }
            publishState(.detached(.channelAborted))
        default:
            publishState(.detached(.channelAborted))
        }
    }

    private func reportImmediateFailure(_ result: ghostty_tmux_result_e, request: Request) {
        preconditionOnWriterQueue()
        guard result != GHOSTTY_TMUX_RESULT_OK else { return }
        reportRequestFailure(request)
        if result == GHOSTTY_TMUX_RESULT_CLIENT_FAILED || result == GHOSTTY_TMUX_RESULT_CLOSED {
            handleClientFailure(result)
        }
    }

    private func reportRequestFailure(_ request: Request) {
        DispatchQueue.main.async { self.callbacks.onRequestFailed(request) }
    }

    private func outstandingAgentMetadataQueries() -> [@Sendable (AgentMetadataQueryResult) -> Void] {
        requestsByToken.values.compactMap {
            guard case .agentMetadata(let completion) = $0 else { return nil }
            return completion
        }
    }

    private func failOutstandingAgentMetadataQueries() {
        preconditionOnWriterQueue()
        let completions = outstandingAgentMetadataQueries()
        requestsByToken = requestsByToken.filter {
            guard case .agentMetadata = $0.value else { return true }
            return false
        }
        completions.forEach { $0(.init(status: .failed, body: "")) }
    }

    private func preconditionOnWriterQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    private func activePaneID(in topology: TopologySnapshot?) -> TmuxPaneID? {
        guard let topology, let windowID = topology.activeWindowID else { return nil }
        return topology.windows.first(where: { $0.id == windowID })?.activePaneID
    }

}

private struct TopologyAccumulator {
    var windows: [TmuxSessionController.WindowInfo] = []
    var panes: [TmuxSessionController.PaneInfo] = []

    mutating func append(_ record: ghostty_tmux_topology_record_s) {
        switch record.tag {
        case GHOSTTY_TMUX_TOPOLOGY_WINDOW:
            let window = record.value.window
            windows.append(TmuxSessionController.WindowInfo(
                id: TmuxWindowID(window.id),
                name: decodeTmuxString(window.name),
                active: window.active,
                zoomed: window.zoomed,
                width: Self.uint32(window.width),
                height: Self.uint32(window.height),
                activePaneID: TmuxPaneID(window.active_pane_id)
            ))
        case GHOSTTY_TMUX_TOPOLOGY_PANE:
            let pane = record.value.pane
            panes.append(TmuxSessionController.PaneInfo(
                id: TmuxPaneID(pane.id),
                windowID: TmuxWindowID(pane.window_id),
                x: Self.uint32(pane.x),
                y: Self.uint32(pane.y),
                width: Self.uint32(pane.width),
                height: Self.uint32(pane.height),
                phase: pane.phase == GHOSTTY_TMUX_PANE_LIVE ? .live : .hydrating
            ))
        default:
            break
        }
    }

    private static func uint32(_ value: Int) -> UInt32 {
        UInt32(clamping: value)
    }
}
