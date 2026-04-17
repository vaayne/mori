import Foundation

// MARK: - IPC Command

/// All commands the `ws` CLI can send to the Mori app over Unix socket.
public enum IPCCommand: Codable, Sendable, Equatable {
    // Project
    case projectList
    case open(path: String)

    // Worktree
    case worktreeList(project: String)
    case worktreeCreate(project: String, branch: String)
    case worktreeDelete(project: String, worktree: String)

    // Window
    case windowList(project: String, worktree: String)
    case windowNew(project: String, worktree: String, name: String?)
    case windowRename(project: String, worktree: String, window: String, newName: String)
    case windowClose(project: String, worktree: String, window: String)

    // Pane
    case paneList(project: String? = nil, worktree: String? = nil, window: String? = nil)
    case paneNew(project: String, worktree: String, window: String, split: String?, name: String?)
    case paneSend(project: String, worktree: String, window: String, pane: String?, keys: String)
    case paneRead(project: String, worktree: String, window: String, pane: String?, lines: Int)
    case paneRename(project: String, worktree: String, window: String, pane: String, newName: String)
    case paneClose(project: String, worktree: String, window: String, pane: String?)
    case paneMessage(project: String, worktree: String, window: String, text: String,
                     senderProject: String? = nil, senderWorktree: String? = nil,
                     senderWindow: String? = nil, senderPaneId: String? = nil)

    // Focus
    case focusProject(project: String)
    case focus(project: String, worktree: String)
    case focusWindow(project: String, worktree: String, window: String)
}

// MARK: - IPC Request

/// A request wrapping an `IPCCommand` with an optional correlation ID.
public struct IPCRequest: Codable, Sendable, Equatable {
    public let command: IPCCommand
    public let requestId: String?

    public init(command: IPCCommand, requestId: String? = nil) {
        self.command = command
        self.requestId = requestId
    }
}

// MARK: - IPC Response

/// The result of processing an `IPCRequest`.
public enum IPCResponse: Codable, Sendable, Equatable {
    case success(payload: Data?)
    case error(message: String)

    /// The correlation ID echoed back from the request.
    public var requestId: String? {
        // Stored externally via IPCResponseEnvelope
        nil
    }
}

/// Wire format: wraps `IPCResponse` with the echoed `requestId`.
public struct IPCResponseEnvelope: Codable, Sendable, Equatable {
    public let response: IPCResponse
    public let requestId: String?

    public init(response: IPCResponse, requestId: String? = nil) {
        self.response = response
        self.requestId = requestId
    }
}

// MARK: - Message Framing

/// Utilities for newline-delimited JSON message framing over the socket.
public enum IPCFraming {

    /// Encode a request to a newline-terminated JSON `Data` blob.
    public static func encode(_ request: IPCRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(request)
        data.append(0x0A) // newline
        return data
    }

    /// Encode a response envelope to a newline-terminated JSON `Data` blob.
    public static func encode(_ envelope: IPCResponseEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(envelope)
        data.append(0x0A) // newline
        return data
    }

    /// Decode a request from a JSON `Data` blob (leading/trailing whitespace tolerated).
    public static func decodeRequest(from data: Data) throws -> IPCRequest {
        let trimmed = data.trimmingNewlines()
        return try JSONDecoder().decode(IPCRequest.self, from: trimmed)
    }

    /// Decode a response envelope from a JSON `Data` blob.
    public static func decodeResponse(from data: Data) throws -> IPCResponseEnvelope {
        let trimmed = data.trimmingNewlines()
        return try JSONDecoder().decode(IPCResponseEnvelope.self, from: trimmed)
    }

    /// Split a data buffer on newline boundaries, returning complete messages
    /// and any remaining incomplete data.
    public static func splitMessages(_ buffer: Data) -> (messages: [Data], remainder: Data) {
        var messages: [Data] = []
        var start = buffer.startIndex
        for i in buffer.indices where buffer[i] == 0x0A {
            let message = buffer[start..<i]
            if !message.isEmpty {
                messages.append(Data(message))
            }
            start = buffer.index(after: i)
        }
        let remainder = Data(buffer[start...])
        return (messages, remainder)
    }
}

// MARK: - Helpers

extension Data {
    /// Trim leading/trailing newline and whitespace bytes.
    func trimmingNewlines() -> Data {
        var start = startIndex
        var end = endIndex
        let whitespace: Set<UInt8> = [0x0A, 0x0D, 0x20, 0x09]
        while start < end, whitespace.contains(self[start]) { start = index(after: start) }
        while end > start, whitespace.contains(self[index(before: end)]) { end = index(before: end) }
        return self[start..<end]
    }
}
