import Foundation

/// An error the herdr server returned in a response envelope.
public struct HerdrServerError: Error, Sendable, Hashable, Codable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

extension HerdrServerError: CustomStringConvertible {
    public var description: String { "\(code): \(message)" }
}

public enum HerdrError: Error, Sendable {
    /// The socket was not reachable — usually no server running for this session.
    case notConnected(path: String, underlying: String)
    /// The server closed the connection before answering.
    case connectionClosed(method: String)
    case timeout(method: String)
    case decodingFailed(method: String, underlying: String)
    /// The server speaks a protocol this client was not written against.
    case unsupportedProtocol(found: Int, minimum: Int, version: String)
    case server(method: String, error: HerdrServerError)

    /// The server-side error code, when the failure came from the server at all.
    public var serverCode: String? {
        guard case .server(_, let error) = self else { return nil }
        return error.code
    }
}

extension HerdrError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notConnected(let path, let underlying):
            return "herdr socket unreachable at \(path): \(underlying)"
        case .connectionClosed(let method):
            return "herdr closed the connection before answering \(method)"
        case .timeout(let method):
            return "herdr did not answer \(method) in time"
        case .decodingFailed(let method, let underlying):
            return "could not decode the \(method) response: \(underlying)"
        case .unsupportedProtocol(let found, let minimum, let version):
            return "herdr \(version) speaks protocol \(found); this build needs \(minimum) or newer"
        case .server(let method, let error):
            return "\(method) failed — \(error)"
        }
    }
}
