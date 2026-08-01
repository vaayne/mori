import Foundation
import Observation
import OSLog
import SwiftUI

#if DEBUG
/// Credential-free simulator smoke route. It deliberately exercises the same
/// facade and view that production uses; the app target never constructs a
/// Ghostty runtime or native surface for this check.
public struct MoriRemoteTerminalProbe: View {
    @State private var model = ProbeModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            if let session = model.session {
                MoriRemoteTerminalView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.didTimeOut {
                ContentUnavailableView("Ghostty renderer failed", systemImage: "exclamationmark.triangle", description: Text(model.status))
            } else {
                ProgressView("Ghostty terminal probe loading")
            }
            Text(model.status).font(.caption).foregroundStyle(model.didTimeOut ? .red : .secondary)
        }
        .padding()
        .accessibilityIdentifier("ghostty-terminal-probe")
        .task { await model.start() }
        .onChange(of: model.session?.isPresentationReady) { _, ready in
            if ready == true { model.recordSuccess() }
        }
        .onDisappear { Task { await model.stop() } }
    }
}

@MainActor
@Observable private final class ProbeModel {
    var session: MoriRemoteTerminalSession?
    var status = "Starting Ghostty tmux transcript…"
    var didTimeOut = false
    private var timeoutTask: Task<Void, Never>?
    private var didRecordResult = false
    private let logger = Logger(subsystem: "com.vaayne.mori-remote", category: "ghostty-probe")

    func recordSuccess() {
        guard !didRecordResult else { return }
        didRecordResult = true
        status = "Ghostty initialized deterministic tmux transcript"
        logger.notice("MORI_GHOSTTY_PROBE_RESULT success=true detail=facade-topology")
    }

    private func recordFailure(_ detail: String) {
        guard !didRecordResult else { return }
        didRecordResult = true
        logger.error("MORI_GHOSTTY_PROBE_RESULT success=false detail=\(detail, privacy: .public)")
    }

    func start() async {
        guard session == nil else { return }
        do {
            let transport = ProbeTransport()
            let session = try MoriRemoteTerminalSession(transport: transport.transport())
            session.onTopologyChange = { [weak self] _ in self?.recordSuccess() }
            self.session = session
            try await session.start()
            timeoutTask = Task { [weak self, weak session] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, !self.didRecordResult, session?.isPresentationReady != true else { return }
                self.didTimeOut = true
                self.status = "No live Ghostty terminal surface arrived within 5 seconds."
                self.recordFailure("presentation-timeout")
            }
        } catch {
            didTimeOut = true
            status = "Ghostty probe failed: \(error.localizedDescription)"
            recordFailure("startup-error")
        }
    }

    func stop() async {
        timeoutTask?.cancel()
        timeoutTask = nil
        await session?.stop()
        session = nil
    }
}

private actor ProbeTransport {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var started = false

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    nonisolated func transport() -> MoriRemoteTerminalTransport {
        .init(
            receivedBytes: receivedBytes,
            start: { try await self.start() },
            send: { _ in },
            close: { _ in await self.close() },
            isActive: { await self.started }
        )
    }

    private func start() throws {
        guard !started else { return }
        started = true
        let pane = "%0;83;44;0;0;1;;;;0;4294967295;4294967295;0;1;0;0;0;0;0;0;0;0;;;0;0;43;8,16\n"
        let window = "$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 probe\n"
        let transcript = "%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n"
            + "%begin 2 2 1\n3.1\n%end 2 2 1\n"
            + "%begin 3 3 1\n\(window)%end 3 3 1\n"
            + "%begin 4 4 1\n\(pane)%end 4 4 1\n"
            + (5...8).map { "%begin \($0) \($0) 1\n%end \($0) \($0) 1\n" }.joined()
        continuation.yield(Data(transcript.utf8))
        continuation.yield(Data("%output %0 MoriRemote Ghostty transcript\\015\\012$ \n".utf8))
    }

    private func close() {
        started = false
        continuation.finish()
    }
}
#endif
