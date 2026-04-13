import Foundation

/// Wire format: `mori-remote:1:<base64url(JSON)>` — shared by Mori (macOS) and MoriRemote (iOS).
public enum MoriRemoteTransferError: Error, Equatable, Sendable {
    case invalidPrefix
    case invalidBase64
    case invalidJSON
    case unsupportedVersion(Int)
    case invalidHost
    case invalidPort
    case invalidUsername
}

/// Connection parameters for importing a MoriRemote server entry from a QR code.
public struct MoriRemoteTransferPayload: Codable, Sendable, Equatable {
    public var v: Int
    public var name: String?
    public var host: String
    public var port: Int
    public var username: String
    public var password: String?
    public var defaultSession: String?

    enum CodingKeys: String, CodingKey {
        case v
        case name
        case host
        case port
        case username
        case password
        case defaultSession
    }

    public init(
        v: Int = 1,
        name: String? = nil,
        host: String,
        port: Int,
        username: String,
        password: String? = nil,
        defaultSession: String? = nil
    ) {
        self.v = v
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.defaultSession = defaultSession
    }

    /// Prefix including version segment, e.g. `mori-remote:1:`.
    public static let qrPrefix = "mori-remote:1:"

    /// Encodes this payload as a single string suitable for QR rendering.
    public func encodeToQRString() throws -> String {
        try Self.validate(host: host, port: port, username: username)
        var copy = self
        copy.v = 1
        let data = try JSONEncoder().encode(copy)
        return Self.qrPrefix + data.base64URLEncodedString()
    }

    /// Parses a scanned QR string into a payload.
    public static func decode(qrString: String) throws -> MoriRemoteTransferPayload {
        let trimmed = qrString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(qrPrefix) else { throw MoriRemoteTransferError.invalidPrefix }
        let b64 = String(trimmed.dropFirst(qrPrefix.count))
        guard let data = Data(base64URLDecoded: b64) else { throw MoriRemoteTransferError.invalidBase64 }
        let decoded: MoriRemoteTransferPayload
        do {
            decoded = try JSONDecoder().decode(MoriRemoteTransferPayload.self, from: data)
        } catch {
            throw MoriRemoteTransferError.invalidJSON
        }
        guard decoded.v == 1 else { throw MoriRemoteTransferError.unsupportedVersion(decoded.v) }
        try validate(host: decoded.host, port: decoded.port, username: decoded.username)
        return decoded
    }

    private static func validate(host: String, port: Int, username: String) throws {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MoriRemoteTransferError.invalidHost }
        guard port > 0, port <= 65535 else { throw MoriRemoteTransferError.invalidPort }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MoriRemoteTransferError.invalidUsername
        }
    }
}

// MARK: - Base64URL

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate init?(base64URLDecoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - s.count % 4
        if pad < 4 {
            s += String(repeating: "=", count: pad)
        }
        self.init(base64Encoded: s)
    }
}
