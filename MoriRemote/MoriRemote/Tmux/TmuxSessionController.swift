import Foundation
import GhosttyKit

struct TmuxWindowID: Hashable, Comparable, Sendable { let rawValue: UInt64; init(_ rawValue: UInt64) { self.rawValue = rawValue }; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }
struct TmuxPaneID: Hashable, Comparable, Sendable { let rawValue: UInt64; init(_ rawValue: UInt64) { self.rawValue = rawValue }; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }

/// Queue-independent admission contract. Native surface pointers remain private to
/// `TmuxSessionController`'s writer queue; tests exercise this value model rather
/// than manufacture a fake native surface.
struct TmuxSurfaceRegistrationLedger: Sendable {
    enum Result: Equatable, Sendable { case registered, unavailable, unknownPane, duplicate, removed, ignored }
    private var registered: [TmuxPaneID: UInt] = [:]
    mutating func register(paneID: TmuxPaneID, identity: UInt, clientAvailable: Bool, retained: Set<TmuxPaneID>) -> Result {
        guard clientAvailable else { return .unavailable }
        guard retained.contains(paneID) else { return .unknownPane }
        guard registered[paneID] == nil else { return .duplicate }
        registered[paneID] = identity
        return .registered
    }
    mutating func unregister(paneID: TmuxPaneID, identity: UInt) -> Result {
        guard registered[paneID] == identity else { return .ignored }
        registered.removeValue(forKey: paneID)
        return .removed
    }
    var isEmpty: Bool { registered.isEmpty }
}

/// Client-local navigation only. Keeping this pure makes the command safety
/// contract testable without inventing a native tmux client.
enum TmuxClientCommandPolicy {
    enum SharedMutation: Sendable { case splitHorizontal, splitVertical, newWindow, closePane }

    static func selectWindow(_ id: TmuxWindowID) -> String { "select-window -t @\(id.rawValue)" }
    static func selectPane(_ id: TmuxPaneID) -> String { "select-pane -t %\(id.rawValue)" }
    /// This static conditional runs only immediately before terminal input. It
    /// never enters copy mode for browsing; it just releases a stale shared mode
    /// so the arriving keystroke remains typeable.
    static let cancelStaleInputMode = "if-shell -F '#{pane_in_mode}' 'send-keys -X cancel' ''"
    /// Fixed command only: agent metadata must stay in Ghostty's correlated
    /// control stream, never a polling SSH channel or a second parser.
    static let agentMetadataQuery = "list-panes -a -F '#{pane_id}\t#{@mori-agent-state}\t#{@mori-agent-name}'"
    static func shared(_ mutation: SharedMutation) -> String {
        switch mutation {
        case .splitHorizontal: "split-window -h"
        case .splitVertical: "split-window -v"
        case .newWindow: "new-window"
        case .closePane: "kill-pane"
        }
    }
    static func isAllowed(_ command: String) -> Bool {
        command.hasPrefix("select-window -t @") || command.hasPrefix("select-pane -t %") ||
            command == cancelStaleInputMode || command == agentMetadataQuery ||
            ["split-window -h", "split-window -v", "new-window", "kill-pane"].contains(command)
    }
}

/// The sole tmux control parser and command admission point. Every client call,
/// parser pump, outbound consume, and surface notification is serialized on
/// `queue`; terminal handles are retained objects with explicit ownership.
final class TmuxSessionController: @unchecked Sendable {
    static let initialHistoryLineLimit = 2_000
    /// Local scrollback is byte-addressed by Ghostty: 10,000 lines × a conservative
    /// 256 bytes/line. Revisit when real transcript telemetry exceeds this budget.
    static let maximumScrollbackBytes = 2_560_000

    struct Window: Equatable, Sendable { let id: TmuxWindowID; let name: String; let active: Bool; let activePaneID: TmuxPaneID }
    struct Pane: Equatable, Sendable { enum Phase: Equatable, Sendable { case hydrating, live }; let id: TmuxPaneID; let windowID: TmuxWindowID; let width: UInt32; let height: UInt32; let phase: Phase }
    struct Topology: Equatable, Sendable {
        let revision: UInt64; let sessionName: String; let windows: [Window]; let panes: [Pane]; let activeWindowID: TmuxWindowID?
        var activePaneID: TmuxPaneID? { guard let activeWindowID else { return nil }; return windows.first(where: { $0.id == activeWindowID })?.activePaneID }
    }
    enum State: Equatable, Sendable { case detached, attaching, ready, closed }
    enum Request: Equatable, Sendable { case selectWindow, selectPane, input }
    enum CommandStatus: Equatable, Sendable { case success, skipped, error }
    struct CommandResult: Equatable, Sendable { let status: CommandStatus; let body: String; let causeToken: UInt64 }
    enum StartError: Swift.Error { case invalidGrid, native(ghostty_tmux_result_e), closed }
    enum SurfaceError: Swift.Error { case unavailable, unknownPane, duplicate }

    /// Ownership is transferred exactly once from the native client to this
    /// object. It may outlive a removed pane and the client, then releases once.
    final class RetainedTerminal: @unchecked Sendable {
        let paneID: TmuxPaneID
        private let native: ghostty_terminal_t
        var handle: ghostty_terminal_t { native }
        init(paneID: TmuxPaneID, handle: ghostty_terminal_t) { self.paneID = paneID; native = handle }
        deinit { ghostty_terminal_release(native) }
    }
    struct Callbacks: Sendable {
        var state: @Sendable (State) -> Void = { _ in }
        var topology: @Sendable (Topology) -> Void = { _ in }
        var terminal: @Sendable (RetainedTerminal) -> Void = { _ in }
        var paneRemoved: @Sendable (TmuxPaneID) -> Void = { _ in }
        var inputFailed: @Sendable (String) -> Void = { _ in }
        var completion: @Sendable (Request, CommandResult) -> Void = { _, _ in }
    }

    let queue: DispatchQueue
    private let callbacks: Callbacks
    private var client: ghostty_tmux_client_t?
    private var sink: (@Sendable (Data) -> Void)?
    private var currentTopology: Topology?
    private var topologyRevision: UInt64 = 0
    private var retainedPaneIDs = Set<TmuxPaneID>()
    /// Opaque identities only. This queue is their only dereferencer.
    private struct NativeSurface: @unchecked Sendable, Equatable { let handle: ghostty_terminal_surface_t; var identity: UInt { UInt(bitPattern: handle) } }
    private var surfaces: [TmuxPaneID: NativeSurface] = [:]
    private var surfaceLedger = TmuxSurfaceRegistrationLedger()
    private var completions: [UInt64: Request] = [:]
    private var trackedInputCompletions: [UInt64: @Sendable (CommandResult) -> Void] = [:]
    private var queryCompletions: [UInt64: @Sendable (CommandResult) -> Void] = [:]
    private var shuttingDown = false

    init(callbacks: Callbacks, queue: DispatchQueue = .init(label: "mori.remote.tmux.writer")) { self.callbacks = callbacks; self.queue = queue }
    deinit { assert(client == nil, "shutdown must free tmux client") }

    func setOutboundSink(_ sink: (@Sendable (Data) -> Void)?) { queue.async { [self] in preconditionWriter(); self.sink = sink } }
    func start(columns: UInt16, rows: UInt16, historyLineLimit: Int = TmuxSessionController.initialHistoryLineLimit, completion: @escaping @Sendable (Result<Void, StartError>) -> Void) {
        queue.async { [self] in
            preconditionWriter()
            guard !shuttingDown, client == nil else { completion(.failure(.closed)); return }
            guard columns > 0, rows > 0 else { completion(.failure(.invalidGrid)); return }
            var config = ghostty_tmux_client_config_new()
            config.userdata = Unmanaged.passUnretained(self).toOpaque()
            config.action_cb = Self.actionCallback
            config.history_line_limit_is_set = true
            config.history_line_limit = min(max(historyLineLimit, Self.initialHistoryLineLimit), RemoteSettings.maximumScrollbackLines)
            config.max_scrollback = Self.maximumScrollbackBytes
            config.initial_columns = columns; config.initial_rows = rows
            var created: ghostty_tmux_client_t?
            let result = ghostty_tmux_client_new(&config, &created)
            guard result == GHOSTTY_TMUX_RESULT_OK, let created else { completion(.failure(.native(result))); return }
            client = created
            publish(.attaching)
            drainOutbound()
            completion(.success(()))
        }
    }

    func transportClosed() { queue.async { [self] in preconditionWriter(); guard !shuttingDown else { return }; failPending(); publish(.detached) } }
    func pump(_ bytes: Data) { queue.async { [self, bytes] in
        preconditionWriter(); guard let client, !shuttingDown else { return }
        let result = bytes.withUnsafeBytes { ghostty_tmux_client_feed(client, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
        guard result == GHOSTTY_TMUX_RESULT_OK else { failPending(); publish(.detached); return }
        drainOutbound()
    } }

    /// Shutdown is valid only after each surface's unregister completion. That
    /// fence ensures no queued terminal_changed call can reach freed memory.
    func shutdown(completion: @escaping @Sendable () -> Void = {}) { queue.async { [self] in
        preconditionWriter(); guard !shuttingDown else { DispatchQueue.main.async(execute: completion); return }
        shuttingDown = true; sink = nil; failPending()
        assert(surfaces.isEmpty && surfaceLedger.isEmpty, "unregister terminal surfaces before controller shutdown")
        currentTopology = nil; retainedPaneIDs.removeAll()
        if let client { let result = ghostty_tmux_client_free(client); assert(result == GHOSTTY_TMUX_RESULT_OK, "tmux client free failed") }
        client = nil; publish(.closed)
        DispatchQueue.main.async(execute: completion)
    } }

    func registerSurface(paneID: TmuxPaneID, surface: ghostty_terminal_surface_t, completion: @escaping @MainActor @Sendable (Result<Void, SurfaceError>) -> Void) {
        let native = NativeSurface(handle: surface)
        queue.async { [self, native] in
            preconditionWriter()
            let admitted = surfaceLedger.register(paneID: paneID, identity: native.identity, clientAvailable: client != nil && !shuttingDown, retained: retainedPaneIDs)
            let result: Result<Void, SurfaceError>
            switch admitted { case .registered: surfaces[paneID] = native; result = .success(()); case .unavailable: result = .failure(.unavailable); case .unknownPane: result = .failure(.unknownPane); default: result = .failure(.duplicate) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func unregisterSurface(paneID: TmuxPaneID, surface: ghostty_terminal_surface_t, completion: @escaping @MainActor @Sendable () -> Void) {
        let native = NativeSurface(handle: surface)
        queue.async { [self, native] in
            preconditionWriter(); _ = surfaceLedger.unregister(paneID: paneID, identity: native.identity)
            if surfaces[paneID] == native { surfaces.removeValue(forKey: paneID) }
            DispatchQueue.main.async { completion() }
        }
    }

    /// These are client-local navigation commands only; no refresh-client,
    /// resize-pane, zoom, or server copy-mode command is admitted here.
    func selectWindow(_ id: TmuxWindowID) { enqueue(TmuxClientCommandPolicy.selectWindow(id), request: .selectWindow) }
    func selectPane(_ id: TmuxPaneID) { enqueue(TmuxClientCommandPolicy.selectPane(id), request: .selectPane) }
    /// Selection is non-mutating. This is called only from an actual input path,
    /// before Ghostty emits the pane bytes, and the writer queue preserves order.
    func prepareForInput() { enqueue(TmuxClientCommandPolicy.cancelStaleInputMode, request: .input) }
    /// The only query result API. The fixed command is correlated by Ghostty's
    /// command token, so callers cannot observe or parse raw control bytes.
    func queryAgentMetadata(completion: @escaping @Sendable (CommandResult) -> Void) {
        enqueueQuery(TmuxClientCommandPolicy.agentMetadataQuery, completion: completion)
    }
    func mutateSharedWorkspace(_ mutation: TmuxClientCommandPolicy.SharedMutation) {
        enqueue(TmuxClientCommandPolicy.shared(mutation), request: .input)
    }
    func sendInput(_ data: Data, to pane: TmuxPaneID, tracked: Bool = false, completion: @escaping @Sendable (CommandResult) -> Void = { _ in }) {
        queue.async { [self, data] in
            preconditionWriter()
            guard let client, !shuttingDown else { completion(.init(status: .error, body: "session unavailable", causeToken: 0)); return }
            if data.isEmpty { completion(.init(status: .success, body: "", causeToken: 0)); return }
            var token: UInt64 = 0
            let result = data.withUnsafeBytes { buffer in tracked ? ghostty_tmux_client_send_pane_input_tracked(client, pane.rawValue, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, &token) : ghostty_tmux_client_send_pane_input(client, pane.rawValue, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count) }
            guard result == GHOSTTY_TMUX_RESULT_OK else { completion(.init(status: .error, body: "\(result)", causeToken: 0)); return }
            if tracked { trackedInputCompletions[token] = completion } else { completion(.init(status: .success, body: "", causeToken: 0)) }
            drainOutbound()
        }
    }

    private func enqueue(_ command: String, request: Request) { queue.async { [self] in
        preconditionWriter(); guard let client, !shuttingDown else { callbacks.completion(request, .init(status: .error, body: "session unavailable", causeToken: 0)); return }
        var token: UInt64 = 0
        let result = command.utf8.withContiguousStorageIfAvailable { ghostty_tmux_client_enqueue_command(client, .init(ptr: $0.baseAddress, len: $0.count), &token) } ?? Array(command.utf8).withUnsafeBufferPointer { ghostty_tmux_client_enqueue_command(client, .init(ptr: $0.baseAddress, len: $0.count), &token) }
        guard result == GHOSTTY_TMUX_RESULT_OK else { callbacks.completion(request, .init(status: .error, body: "\(result)", causeToken: 0)); return }
        completions[token] = request; drainOutbound()
    } }

    private func enqueueQuery(_ command: String, completion: @escaping @Sendable (CommandResult) -> Void) {
        queue.async { [self] in
            preconditionWriter()
            guard let client, !shuttingDown else {
                completion(.init(status: .error, body: "session unavailable", causeToken: 0))
                return
            }
            var token: UInt64 = 0
            let result = command.utf8.withContiguousStorageIfAvailable {
                ghostty_tmux_client_enqueue_command(client, .init(ptr: $0.baseAddress, len: $0.count), &token)
            } ?? Array(command.utf8).withUnsafeBufferPointer {
                ghostty_tmux_client_enqueue_command(client, .init(ptr: $0.baseAddress, len: $0.count), &token)
            }
            guard result == GHOSTTY_TMUX_RESULT_OK else {
                completion(.init(status: .error, body: "\(result)", causeToken: 0))
                return
            }
            queryCompletions[token] = completion
            drainOutbound()
        }
    }

    private func drainOutbound() {
        preconditionWriter(); guard let client else { return }
        var bytes = ghostty_tmux_bytes_s()
        guard ghostty_tmux_client_outbound(client, &bytes) == GHOSTTY_TMUX_RESULT_OK else { failPending(); publish(.detached); return }
        guard bytes.len > 0, let pointer = bytes.ptr else { return }
        let owned = Data(bytes: pointer, count: bytes.len)
        guard ghostty_tmux_client_consume(client, bytes.len) == GHOSTTY_TMUX_RESULT_OK else { failPending(); publish(.detached); return }
        sink?(owned)
    }

    private static let actionCallback: ghostty_tmux_action_cb = { userdata, action in
        guard let userdata, let action else { return }
        Unmanaged<TmuxSessionController>.fromOpaque(userdata).takeUnretainedValue().handle(action.pointee)
    }
    private func handle(_ action: ghostty_tmux_action_s) {
        preconditionWriter()
        switch action.tag {
        case GHOSTTY_TMUX_ACTION_TOPOLOGY: handleTopology(action.value.topology)
        case GHOSTTY_TMUX_ACTION_PANE_CHANGED: handlePaneChanged(TmuxPaneID(action.value.pane_id))
        case GHOSTTY_TMUX_ACTION_COMMAND_COMPLETE: handleCommand(action.value.command)
        case GHOSTTY_TMUX_ACTION_INPUT_FAILED: callbacks.inputFailed(decode(action.value.input_failure))
        case GHOSTTY_TMUX_ACTION_EXIT: failPending(); publish(.detached)
        default: break // Forward-compatible ABI tags must not tear down a healthy attachment.
        }
    }
    private func handleTopology(_ action: ghostty_tmux_topology_action_s) {
        preconditionWriter(); var accumulator = TopologyAccumulator()
        let result = withUnsafeMutablePointer(to: &accumulator) { ghostty_tmux_topology_visit(action.view, UnsafeMutableRawPointer($0), { raw, record in guard let raw, let record else { return }; raw.assumingMemoryBound(to: TopologyAccumulator.self).pointee.append(record.pointee) }) }
        guard result == GHOSTTY_TMUX_RESULT_OK else { failPending(); publish(.detached); return }
        topologyRevision &+= 1
        let snapshot = Topology(revision: topologyRevision, sessionName: decode(action.session_name), windows: accumulator.windows, panes: accumulator.panes, activeWindowID: accumulator.windows.first(where: \.active)?.id)
        let removed = Set(currentTopology?.panes.map(\.id) ?? []).subtracting(snapshot.panes.map(\.id))
        currentTopology = snapshot
        // Retained references may outlive panes; dropping our ID ownership lets
        // the presentation owner release them after its unregister fence.
        removed.forEach { retainedPaneIDs.remove($0) }
        let callbacks = callbacks
        DispatchQueue.main.async { removed.sorted().forEach(callbacks.paneRemoved) }
        // A live pane can be materialized immediately. Hydrating panes wait for
        // their authoritative PANE_CHANGED completion.
        for pane in snapshot.panes where pane.phase == .live { retainTerminal(pane.id) }
        publish(.ready)
        DispatchQueue.main.async { callbacks.topology(snapshot) }
    }
    private func handlePaneChanged(_ paneID: TmuxPaneID) {
        preconditionWriter(); retainTerminal(paneID)
        // Registration precedes notification; a new surface receives an initial
        // explicit terminalChanged in its MainActor owner after registration.
        if let surface = surfaces[paneID] { _ = ghostty_terminal_surface_terminal_changed(surface.handle) }
    }
    private func retainTerminal(_ paneID: TmuxPaneID) {
        preconditionWriter(); guard retainedPaneIDs.insert(paneID).inserted, let client else { return }
        var terminal: ghostty_terminal_t?
        guard ghostty_tmux_client_retain_pane_terminal(client, paneID.rawValue, &terminal) == GHOSTTY_TMUX_RESULT_OK, let terminal else { retainedPaneIDs.remove(paneID); return }
        let handoff = RetainedTerminal(paneID: paneID, handle: terminal); let callbacks = callbacks
        DispatchQueue.main.async { callbacks.terminal(handoff) }
    }
    private func handleCommand(_ command: ghostty_tmux_command_completion_s) {
        preconditionWriter()
        let status: CommandStatus = command.status == GHOSTTY_TMUX_COMMAND_SUCCESS ? .success : command.status == GHOSTTY_TMUX_COMMAND_SKIPPED ? .skipped : .error
        let result = CommandResult(status: status, body: decode(command.body), causeToken: command.cause_token)
        if let callback = trackedInputCompletions.removeValue(forKey: command.token) { callback(result) }
        if let callback = queryCompletions.removeValue(forKey: command.token) { callback(result) }
        if let request = completions.removeValue(forKey: command.token) { callbacks.completion(request, result) }
    }
    private func failPending() {
        let result = CommandResult(status: .error, body: "transport closed", causeToken: 0)
        let commands = completions.values; completions.removeAll(); commands.forEach { callbacks.completion($0, result) }
        let inputs = trackedInputCompletions.values; trackedInputCompletions.removeAll(); inputs.forEach { $0(result) }
        let queries = queryCompletions.values; queryCompletions.removeAll(); queries.forEach { $0(result) }
    }
    private func publish(_ state: State) { let callbacks = callbacks; DispatchQueue.main.async { callbacks.state(state) } }
    private func preconditionWriter() { dispatchPrecondition(condition: .onQueue(queue)) }
}

private func decode(_ bytes: ghostty_tmux_bytes_s) -> String { guard let pointer = bytes.ptr, bytes.len > 0 else { return "" }; return String(decoding: UnsafeBufferPointer(start: pointer, count: bytes.len), as: UTF8.self) }
private struct TopologyAccumulator {
    var windows: [TmuxSessionController.Window] = []; var panes: [TmuxSessionController.Pane] = []
    mutating func append(_ record: ghostty_tmux_topology_record_s) { switch record.tag {
    case GHOSTTY_TMUX_TOPOLOGY_WINDOW: let value = record.value.window; windows.append(.init(id: .init(value.id), name: decode(value.name), active: value.active, activePaneID: .init(value.active_pane_id)))
    case GHOSTTY_TMUX_TOPOLOGY_PANE: let value = record.value.pane; panes.append(.init(id: .init(value.id), windowID: .init(value.window_id), width: UInt32(clamping: value.width), height: UInt32(clamping: value.height), phase: value.phase == GHOSTTY_TMUX_PANE_LIVE ? .live : .hydrating))
    default: break
    } }
}
