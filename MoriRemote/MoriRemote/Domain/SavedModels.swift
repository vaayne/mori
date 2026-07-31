import Foundation

/// A saved SSH endpoint. Credentials deliberately live outside this JSON model.
struct SavedServer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var identityID: UUID
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        identityID: UUID? = nil,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.identityID = identityID ?? id
        self.lastConnectedAt = lastConnectedAt
    }

    var endpoint: CanonicalEndpoint? { try? CanonicalEndpoint(host: host, port: port) }

    func validated() throws -> SavedServer {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SavedModelValidationError.emptyName
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SavedModelValidationError.emptyUsername
        }
        _ = try CanonicalEndpoint(host: host, port: port)
        return self
    }
}

struct SavedWorkspace: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var serverID: UUID
    var name: String
    var tmuxSession: String
    var lastConnectedAt: Date?

    init(id: UUID = UUID(), serverID: UUID, name: String, tmuxSession: String, lastConnectedAt: Date? = nil) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.tmuxSession = tmuxSession
        self.lastConnectedAt = lastConnectedAt
    }

    func validated() throws -> SavedWorkspace {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SavedModelValidationError.emptyName
        }
        guard !tmuxSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tmuxSession.contains(where: { $0.isNewline || $0 == "\0" }) else {
            throw SavedModelValidationError.invalidTmuxSession
        }
        return self
    }
}

enum SSHIdentityKind: String, Codable, Sendable {
    case password
    case privateKey
}

struct SSHIdentity: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var serverID: UUID
    var kind: SSHIdentityKind
    var label: String

    init(id: UUID = UUID(), serverID: UUID, kind: SSHIdentityKind, label: String = "") {
        self.id = id
        self.serverID = serverID
        self.kind = kind
        self.label = label
    }

    func validated() throws -> SSHIdentity {
        guard !label.contains(where: { $0.isNewline || $0 == "\0" }) else {
            throw SavedModelValidationError.invalidIdentityLabel
        }
        return self
    }
}

struct RemoteSettings: Codable, Equatable, Sendable {
    static let `default` = RemoteSettings()
    static let maximumScrollbackLines = 10_000

    var initialScrollbackLines: Int
    var maximumScrollbackLines: Int

    init(initialScrollbackLines: Int = 2_000, maximumScrollbackLines: Int = 10_000) {
        self.initialScrollbackLines = initialScrollbackLines
        self.maximumScrollbackLines = maximumScrollbackLines
    }

    func validated() throws -> RemoteSettings {
        guard initialScrollbackLines > 0,
              maximumScrollbackLines >= initialScrollbackLines,
              maximumScrollbackLines <= Self.maximumScrollbackLines else {
            throw SavedModelValidationError.invalidScrollbackLimit
        }
        return self
    }
}

enum SavedModelValidationError: Error, Equatable, Sendable {
    case emptyName
    case emptyUsername
    case invalidHost
    case invalidPort
    case invalidTmuxSession
    case invalidIdentityLabel
    case invalidScrollbackLimit
}

struct CanonicalEndpoint: Codable, Equatable, Hashable, Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let unbracketed = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            ? String(trimmed.dropFirst().dropLast())
            : trimmed
        let canonical = unbracketed.hasSuffix(".") ? String(unbracketed.dropLast()) : unbracketed

        guard !canonical.isEmpty,
              !canonical.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\0" }) else {
            throw SavedModelValidationError.invalidHost
        }
        guard (1...65_535).contains(port) else { throw SavedModelValidationError.invalidPort }
        self.host = canonical.lowercased()
        self.port = port
    }
}

struct TrustedHost: Codable, Equatable, Sendable {
    let serverID: UUID
    let endpoint: CanonicalEndpoint
    let algorithm: String
    let fingerprint: String
    let trustedAt: Date
}

protocol CredentialReading: Sendable {
    func password(for identityID: UUID) throws -> String?
}

enum CredentialRequirement: Equatable, Sendable {
    case available
    /// Presentation localizes this state in the future connection flow.
    case credentialRequired
}

func credentialRequirement(identityID: UUID, credentials: any CredentialReading) throws -> CredentialRequirement {
    try credentials.password(for: identityID) == nil ? .credentialRequired : .available
}
