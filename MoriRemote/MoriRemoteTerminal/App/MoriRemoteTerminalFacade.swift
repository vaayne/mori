import Foundation
import SwiftUI

/// App-owned SSH is reduced to this sans-I/O boundary. It deliberately has no
/// Citadel, persistence, account, or arbitrary tmux-command vocabulary.
public enum MoriRemoteTerminalCloseDisposition: Sendable { case reusable, invalidated }

public struct MoriRemoteTerminalTransport: Sendable {
    public let receivedBytes: AsyncThrowingStream<Data, Error>
    public let start: @Sendable () async throws -> Void
    public let send: @Sendable (Data) async throws -> Void
    public let close: @Sendable (MoriRemoteTerminalCloseDisposition) async -> Void
    public let isActive: @Sendable () async -> Bool

    public init(
        receivedBytes: AsyncThrowingStream<Data, Error>,
        start: @escaping @Sendable () async throws -> Void,
        send: @escaping @Sendable (Data) async throws -> Void,
        close: @escaping @Sendable (MoriRemoteTerminalCloseDisposition) async -> Void,
        isActive: @escaping @Sendable () async -> Bool
    ) {
        self.receivedBytes = receivedBytes
        self.start = start
        self.send = send
        self.close = close
        self.isActive = isActive
    }
}

private struct ClosureTmuxControlTransport: TmuxControlTransport, TmuxControlTransportLivenessChecking {
    let base: MoriRemoteTerminalTransport
    var receivedBytes: AsyncThrowingStream<Data, Error> { base.receivedBytes }
    func start(initialViewport: TmuxControlViewport?) async throws { _ = initialViewport; try await base.start() }
    func send(_ data: Data) async throws { try await base.send(data) }
    func close(disposition: TmuxControlTransportCloseDisposition) async {
        await base.close(disposition == .reusable ? .reusable : .invalidated)
    }
    func isControlChannelActive() async -> Bool { await base.isActive() }
}

public enum MoriRemoteTerminalConnectionState: Equatable, Sendable {
    case connecting, ready, disconnected
}

public enum MoriRemoteTerminalNavigatorScope: Sendable {
    case sessions, windows, panes
}

enum MoriRemoteTerminalConnectionProjection {
    static func applying(_ incoming: MoriRemoteTerminalConnectionState, hasTopology: Bool) -> MoriRemoteTerminalConnectionState {
        incoming == .connecting && hasTopology ? .ready : incoming
    }
}

public struct MoriRemoteTerminalPane: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let windowID: UInt64
    public let columns: UInt32
    public let rows: UInt32
    public init(id: UInt64, windowID: UInt64, columns: UInt32, rows: UInt32) {
        self.id = id; self.windowID = windowID; self.columns = columns; self.rows = rows
    }
}

public struct MoriRemoteTerminalWindow: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let title: String
    public let active: Bool
    public let activePaneID: UInt64?
    public init(id: UInt64, title: String, active: Bool, activePaneID: UInt64?) {
        self.id = id; self.title = title; self.active = active; self.activePaneID = activePaneID
    }
}

public struct MoriRemoteTerminalTopology: Equatable, Sendable {
    public let windows: [MoriRemoteTerminalWindow]
    public let panes: [MoriRemoteTerminalPane]
    public let activeWindowID: UInt64?
    public init(windows: [MoriRemoteTerminalWindow], panes: [MoriRemoteTerminalPane], activeWindowID: UInt64?) {
        self.windows = windows; self.panes = panes; self.activeWindowID = activeWindowID
    }
}

public struct MoriRemoteTerminalAgentMetadataResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case success, skipped, failed }
    public let status: Status
    public let body: String
}

public enum MoriRemoteTerminalSharedMutation: Sendable {
    case newWindow, splitHorizontal, splitVertical, closePane, closeWindow
}

/// App-owned SSH uploads an image and returns the shell-visible remote path.
/// The terminal module owns picker/staging UI but never credentials or roots.
public struct MoriRemoteTerminalImageUploader: Sendable {
    public typealias ProgressHandler = @Sendable (Int64, Int64) async -> Void
    private let uploadHandler: @Sendable (URL, String, @escaping ProgressHandler) async throws -> String

    public init(
        upload: @escaping @Sendable (URL, String, @escaping ProgressHandler) async throws -> String
    ) {
        uploadHandler = upload
    }

    public func upload(
        localURL: URL,
        filename: String,
        progress: @escaping ProgressHandler
    ) async throws -> String {
        try await uploadHandler(localURL, filename, progress)
    }
}

/// The sole public native-terminal owner. It retains GhosttyKitRuntime before
/// constructing the tmux client, so callers cannot repeat an uninitialized
/// native harness or leak Ghostty handles into the application target.
@MainActor
public final class MoriRemoteTerminalSession {
    public let instanceID: UUID
    public private(set) var connectionState: MoriRemoteTerminalConnectionState = .connecting
    public private(set) var topology: MoriRemoteTerminalTopology?
    public private(set) var lastError: String?

    public var onConnectionStateChange: (@MainActor (MoriRemoteTerminalConnectionState) -> Void)?
    public var onTopologyChange: (@MainActor (MoriRemoteTerminalTopology) -> Void)?

    private let runtime: GhosttyKitRuntime
    private let terminalSession: TmuxTerminalSession
    fileprivate let screenAdapter: TmuxTerminalScreenAdapter

    public init(
        transport: MoriRemoteTerminalTransport,
        initialScrollbackLines: Int = 2_000,
        instanceID: UUID = UUID()
    ) throws {
        self.instanceID = instanceID
        let runtime = try GhosttyKitRuntime()
        self.runtime = runtime
        let terminalSession = TmuxTerminalSession(
            app: runtime.appHandle,
            transport: ClosureTmuxControlTransport(base: transport),
            historyLineLimit: initialScrollbackLines,
            baseSurfaceConfig: { runtime.makeTmuxBaseSurfaceConfig() },
            paneViewTheme: { .ghosttyDefault }
        )
        let screenAdapter = TmuxTerminalScreenAdapter()
        self.terminalSession = terminalSession
        self.screenAdapter = screenAdapter
        screenAdapter.activate(
            session: terminalSession,
            initialViewportHandler: { [weak terminalSession] size, scale in
                terminalSession?.updateViewportMetrics(size: size, scale: scale)
            }
        )
        terminalSession.onStateChange = { [weak self] state in self?.receive(state) }
        terminalSession.onTopologyChange = { [weak self] snapshot in self?.receive(snapshot) }
    }

    public func start() async throws {
        do {
            try await terminalSession.connect()
        } catch {
            lastError = error.localizedDescription
            publishConnectionState(.disconnected)
            throw error
        }
    }

    public func stop() async {
        screenAdapter.invalidate()
        await terminalSession.shutdown()
        publishConnectionState(.disconnected)
    }

    public func setPresentationActive(_ active: Bool) {
        terminalSession.setAppActive(active)
    }

    public func isControlChannelActive() async -> Bool { await terminalSession.controlChannelIsActive() }

    public func selectWindow(_ id: UInt64) { terminalSession.controller.requestSelectWindow(windowID: .init(id)) }
    public func selectPane(_ id: UInt64) { terminalSession.controller.requestSelectPane(paneID: .init(id)) }
    public func queryAgentMetadata() async -> MoriRemoteTerminalAgentMetadataResult {
        await withCheckedContinuation { continuation in
            terminalSession.controller.queryAgentMetadata { result in
                let status: MoriRemoteTerminalAgentMetadataResult.Status = switch result.status {
                case .success: .success; case .skipped: .skipped; case .failed: .failed
                }
                continuation.resume(returning: .init(status: status, body: result.body))
            }
        }
    }

    public func performSharedMutation(_ mutation: MoriRemoteTerminalSharedMutation) {
        let value: TmuxSessionController.SharedMutation = switch mutation {
        case .newWindow: .newWindow; case .splitHorizontal: .splitHorizontal
        case .splitVertical: .splitVertical; case .closePane: .closePane; case .closeWindow: .closeWindow
        }
        terminalSession.controller.requestSharedMutation(value)
    }

    private func receive(_ state: TmuxSessionController.SessionState) {
        switch state {
        case .ready:
            lastError = nil
            publishConnectionState(.ready)
        case .attaching, .syncing:
            // Topology proves the control client is usable. A delayed syncing
            // callback must not regress an already rendered terminal to Connecting.
            publishConnectionState(MoriRemoteTerminalConnectionProjection.applying(.connecting, hasTopology: topology != nil))
        case .detached, .closed:
            publishConnectionState(.disconnected)
        }
    }

    private func receive(_ snapshot: TmuxSessionController.TopologySnapshot) {
        let topology = MoriRemoteTerminalTopology(
            windows: snapshot.windows.map { .init(id: $0.id.rawValue, title: $0.name, active: $0.active, activePaneID: $0.activePaneID?.rawValue) },
            panes: snapshot.panes.map { .init(id: $0.id.rawValue, windowID: $0.windowID.rawValue, columns: $0.width, rows: $0.height) },
            activeWindowID: snapshot.activeWindowID?.rawValue
        )
        self.topology = topology
        onTopologyChange?(topology)
    }

    private func publishConnectionState(_ state: MoriRemoteTerminalConnectionState) {
        guard connectionState != state else { return }
        connectionState = state
        onConnectionStateChange?(state)
    }
}

public struct MoriRemoteTerminalView: View {
    private let session: MoriRemoteTerminalSession
    private let isInputSuspended: Bool
    private let imageUploader: MoriRemoteTerminalImageUploader?
    private let onShowNavigator: (MoriRemoteTerminalNavigatorScope) -> Void
    private let onShowLibrary: () -> Void
    private let onSharedMutationRequest: (MoriRemoteTerminalSharedMutation) -> Void

    public init(
        session: MoriRemoteTerminalSession,
        isInputSuspended: Bool = false,
        imageUploader: MoriRemoteTerminalImageUploader? = nil,
        onShowNavigator: @escaping (MoriRemoteTerminalNavigatorScope) -> Void = { _ in },
        onShowLibrary: @escaping () -> Void = {},
        onSharedMutationRequest: @escaping (MoriRemoteTerminalSharedMutation) -> Void = { _ in }
    ) {
        self.session = session
        self.isInputSuspended = isInputSuspended
        self.imageUploader = imageUploader
        self.onShowNavigator = onShowNavigator
        self.onShowLibrary = onShowLibrary
        self.onSharedMutationRequest = onSharedMutationRequest
    }

    public var body: some View {
        GhosttyTerminalCoreView(
            screen: session.screenAdapter,
            isInputSuspended: isInputSuspended,
            imageUploader: imageUploader,
            onShowNavigator: onShowNavigator,
            onShowLibrary: onShowLibrary,
            onSharedMutationRequest: onSharedMutationRequest
        )
    }
}
