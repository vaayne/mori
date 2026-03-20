#!/usr/bin/env bash
# Shared functions for Mori agent hook scripts.
# Sourced by mori-agent-hook.sh and mori-codex-hook.sh.

# Requires AGENT_NAME to be set by the sourcing script.

set_state() {
    local state="$1"
    tmux set-option -p @mori-agent-state "$state"
    tmux set-option -p @mori-agent-name "$AGENT_NAME"
    # rename-window implicitly disables automatic-rename;
    # stale cleanup re-enables it so tmux picks up the current process name.
    tmux rename-window "$AGENT_NAME"
}
