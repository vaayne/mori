#!/usr/bin/env bash
# Local tmux semantics only; it never contacts an SSH host or user workspace.
set -euo pipefail
socket="mori-remote-phase2-${RANDOM}-${RANDOM}"
source="mori-remote-source-${RANDOM}"
shadow="${source}--mori-remote-shadow"
cleanup() {
  tmux -L "$socket" kill-server 2>/dev/null || true
}
trap cleanup EXIT

tmux -L "$socket" new-session -d -s "$source"
tmux -L "$socket" new-session -d -t "$source" -s "$shadow"
format=$'#{session_name}\t#{session_group}'
actual=$(tmux -L "$socket" display-message -p -t "$shadow" "$format")
expected="$shadow"$'\t'"$source"
if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected grouped session metadata: %q (expected %q)\n' "$actual" "$expected" >&2
  exit 1
fi
tmux -L "$socket" kill-session -t "$shadow"
tmux -L "$socket" has-session -t "$source"
if tmux -L "$socket" has-session -t "$shadow" 2>/dev/null; then
  echo 'shadow still exists after exact cleanup' >&2
  exit 1
fi
printf 'tmux grouped shadow cleanup contract passed\n'
