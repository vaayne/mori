#!/usr/bin/env bash
# Shared functions for Mori agent hook scripts.
# Sourced by mori-agent-hook.sh and mori-codex-hook.sh.

# Requires AGENT_NAME to be set by the sourcing script.
# Target the exact pane that triggered the hook. Without `-t "$TMUX_PANE"`, tmux
# falls back to the active pane for the current client/session, which can stamp the
# wrong pane when multiple agent panes share a session.

set_state() {
    local state="$1"
    local pane_target="${TMUX_PANE:-}"
    [ -z "$pane_target" ] && exit 0

    tmux set-option -p -t "$pane_target" @mori-agent-state "$state"
    tmux set-option -p -t "$pane_target" @mori-agent-name "$AGENT_NAME"
    tmux select-pane -t "$pane_target" -T "$AGENT_NAME"
}
