# Failure Modes and Fixes

## Window name changed

**Symptom:** `Error: Window not found: agent-kit/main/shell` or commands targeting a window silently fail.

**Cause:** Ghostty renames the tab whenever any pane in it updates its terminal title. This happens on every agent launch or version banner.

**Fix:** Look up the current window name by stable pane ID, or skip window names entirely:

```bash
# Look up current window name
mori pane list --json | jq '.[] | select(.tmuxPaneId=="%56")'

# Better: skip window names, use tmux directly
tmux send-keys -t %56 'your text' Enter
```

---

## Message dropped silently

**Symptom:** `mori pane send --pane %<id>` returns `{"status":"ok"}` but nothing appears in the target pane.

**Cause:** `mori pane send` only reliably delivers to the window's *active* pane. The `--pane` flag is accepted but observed to drop in testing when the target is not active.

**Fix:** Use tmux directly — it reaches any pane regardless of active status:

```bash
tmux send-keys -t %56 'your text' Enter
tmux capture-pane -t %56 -p | tail -10  # verify delivery
```

---

## Text landed in the shell, not the agent

**Symptom:** Your message ran as a shell command instead of being sent to the agent.

**Cause:** You sent before the agent was fully started. The pane was still at the shell prompt.

**Fix:** Always wait for the agent's banner/prompt to appear before sending the real request:

```bash
sleep 3 && tmux capture-pane -t %60 -p | tail -10
# confirm agent prompt is visible, then send
```

---

## Prompt queued but not submitted

**Symptom:** The agent shows your text in its input area but is not processing it.

**Fix:** Send Enter explicitly:

```bash
tmux send-keys -t %60 Enter
sleep 2 && tmux capture-pane -t %60 -p | tail -10
```

---

## Agent cannot edit files

**Symptom:** Agent says `Write` or `Edit` is denied.

**Cause:** Launched without an edit-capable permission mode.

**Fix:** Restart with the right mode:

```bash
tmux send-keys -t %60 C-c
tmux send-keys -t %60 'cd /path/to/repo && claude --model sonnet --permission-mode acceptEdits' Enter
```

---

## Agent confused / stuck in bad state

**Symptom:** Agent is not responding normally, seems to be looping, or ignoring input.

**Fix:** Interrupt, re-read, then retry:

```bash
tmux send-keys -t %60 C-c
sleep 1
tmux capture-pane -t %60 -p | tail -20
# then resend your request cleanly
```

---

## `mori pane message` reached the wrong agent

**Symptom:** Message went to the wrong agent in the window (e.g., the shell pane instead of pi).

**Cause:** `mori pane message` routes to the window's *active* agent — if you clicked into a different pane, the active agent shifted.

**Fix:** Use `tmux send-keys -t %<id>` to target a specific pane regardless of which is active:

```bash
tmux send-keys -t %56 '[FROM:claude:%31 TO:pi:%56] your message' Enter
```
