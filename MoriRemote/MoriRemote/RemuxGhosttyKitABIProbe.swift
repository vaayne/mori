import GhosttyKit

/// Compile-time contract for the sans-I/O tmux ABI required by the remux rewrite.
/// This is intentionally unused: Phase 0 must not alter the existing terminal flow.
@MainActor
enum RemuxGhosttyKitABIProbe {
    static let tmuxClientConfigConstructor: () -> ghostty_tmux_client_config_s =
        ghostty_tmux_client_config_new
}
