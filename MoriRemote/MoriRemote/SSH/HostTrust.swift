import Foundation

enum SSHHostTrustKind: Equatable, Sendable { case unknown, changed }
struct SSHHostTrustChallenge: Equatable, Sendable {
    let kind: SSHHostTrustKind; let serverID: UUID; let endpoint: CanonicalEndpoint
    let algorithm: String; let receivedFingerprint: String; let trustedFingerprint: String?
}
enum SSHHostTrustError: Error, Equatable, Sendable, LocalizedError {
    case trustRequired(SSHHostTrustChallenge)
    case changedKey(SSHHostTrustChallenge)
    case staleChallenge

    var errorDescription: String? {
        switch self {
        case .trustRequired:
            String(localized: "The SSH host key is unknown. Review and trust it before connecting.")
        case .changedKey:
            String(localized: "The SSH host key changed. Connection refused.")
        case .staleChallenge:
            String(localized: "The SSH host-key confirmation is no longer valid. Try again.")
        }
    }
}

/// Pure, fail-closed trust gate. A network adapter must call this before opening any child channel.
struct SSHHostTrustResolver: Sendable {
    let store: TrustedHostStore
    func verify(server: SavedServer, algorithm: String, fingerprint: String) throws {
        guard let endpoint = server.endpoint else { throw SavedModelValidationError.invalidHost }
        guard let trusted = try store.trustedHost(for: server.id, endpoint: endpoint) else {
            throw SSHHostTrustError.trustRequired(.init(kind: .unknown, serverID: server.id, endpoint: endpoint, algorithm: algorithm, receivedFingerprint: fingerprint, trustedFingerprint: nil))
        }
        guard trusted.algorithm == algorithm, trusted.fingerprint == fingerprint else {
            let challenge = SSHHostTrustChallenge(kind: .changed, serverID: server.id, endpoint: endpoint, algorithm: algorithm, receivedFingerprint: fingerprint, trustedFingerprint: trusted.fingerprint)
            throw SSHHostTrustError.changedKey(challenge)
        }
    }
    func explicitlyTrust(_ challenge: SSHHostTrustChallenge, replaceChanged: Bool = false, now: Date = .now) throws {
        let current = try store.trustedHost(for: challenge.serverID, endpoint: challenge.endpoint)
        switch challenge.kind {
        case .unknown: guard current == nil else { throw SSHHostTrustError.staleChallenge }
        case .changed: guard replaceChanged, current?.fingerprint == challenge.trustedFingerprint else { throw SSHHostTrustError.staleChallenge }
        }
        try store.trust(.init(serverID: challenge.serverID, endpoint: challenge.endpoint, algorithm: challenge.algorithm, fingerprint: challenge.receivedFingerprint, trustedAt: now))
    }
}
