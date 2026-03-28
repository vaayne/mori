import Foundation

/// SSH authentication method configuration.
/// Key data is raw PEM/OpenSSH bytes (not a file path — iOS has no ~/.ssh/).
public enum SSHAuthMethod: Sendable {
    /// Password-based authentication (primary for spike).
    case password(String)

    /// Public key authentication using raw key data (stretch goal).
    /// `privateKey` is the raw PEM or OpenSSH key bytes imported from the iOS file picker or pasted.
    case publicKey(privateKey: Data, passphrase: String?)
}
