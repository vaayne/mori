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
                guard !Task.isCancelled, let self, !self.didRecordResult, session != nil else { return }
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
    private var viewport: TmuxControlViewport?
    private var nextCommandNumber = 2
    private var hydrationCommandCount = 0
    private var didSendOutput = false

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    nonisolated func transport() -> MoriRemoteTerminalTransport {
        .init(
            receivedBytes: receivedBytes,
            start: { try await self.start(viewport: $0) },
            send: { try await self.send($0) },
            close: { _ in await self.close() },
            isActive: { await self.started }
        )
    }

    private func start(viewport: TmuxControlViewport) throws {
        guard !started else { return }
        started = true
        self.viewport = viewport
        continuation.yield(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
    }

    private func send(_ data: Data) throws {
        guard started, let viewport else { return }
        let commands = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .flatMap { $0.components(separatedBy: " ; ") }
            .filter { !$0.isEmpty }

        for command in commands {
            let body: String
            if command.contains("#{version}") {
                body = "3.1\n"
            } else if command.hasPrefix("list-windows ") {
                body = Self.windowRecord(viewport: viewport)
            } else if command.hasPrefix("display-message -p -t %0 ") {
                body = Self.paneState(viewport: viewport)
                hydrationCommandCount += 1
            } else {
                body = ""
                if command.hasPrefix("capture-pane ") {
                    hydrationCommandCount += 1
                }
            }
            let number = nextCommandNumber
            nextCommandNumber += 1
            continuation.yield(Data(
                "%begin \(number) \(number) 1\n\(body)%end \(number) \(number) 1\n".utf8
            ))
        }

        if hydrationCommandCount >= 5, !didSendOutput {
            didSendOutput = true
            continuation.yield(Data("%output %0 MoriRemote Ghostty transcript\\015\\012$ \n".utf8))
        }
    }

    private static func windowRecord(viewport: TmuxControlViewport) -> String {
        let layoutBody = "\(viewport.columns)x\(viewport.rows),0,0,0"
        let layout = "\(tmuxLayoutChecksum(layoutBody)),\(layoutBody)"
        return "$42 @0 1 %0 \(viewport.columns) \(viewport.rows) \(layout) \(layout) probe\n"
    }

    private static func paneState(viewport: TmuxControlViewport) -> String {
        let cursorY = viewport.rows - 1
        return "%0;\(viewport.columns);\(viewport.rows);0;0;1;;;;0;4294967295;4294967295;0;1;0;0;0;0;0;0;0;0;;;0;0;\(cursorY);8,16\n"
    }

    private static func tmuxLayoutChecksum(_ layout: String) -> String {
        let checksum = layout.utf8.reduce(UInt16(0)) { checksum, byte in
            let rotated = (checksum >> 1) | ((checksum & 1) << 15)
            return rotated &+ UInt16(byte)
        }
        return String(format: "%04x", checksum)
    }

    private func close() {
        started = false
        continuation.finish()
    }
}
#endif
