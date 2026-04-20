# Workflows

## Workflow A: Launch a helper agent in a split pane

Use when you need a new agent for review, subtask, or pair work.

### 1. Discover the target window

```bash
# Inside a mori pane — MORI_PROJECT and MORI_WORKTREE are already set
mori pane list --json | jq --arg p "$MORI_PROJECT" --arg w "$MORI_WORKTREE" \
  '.[] | select(.projectName==$p and .worktreeName==$w)'
```

Note the `windowName`. This is the **only step** where window name is needed — `pane new` requires it as a bootstrap input. After splitting, switch to `tmuxPaneId` exclusively.

### 2. Split a new pane

```bash
mori pane new --project myapp --worktree main --window <window-name> --split v --name helper --json
# → {"paneId": "%60", "window": "..."}
```

Immediately re-list to capture `tmuxPaneId` — window name may have already changed:

```bash
mori pane list --json | jq '.[] | select(.paneTitle=="helper") | .tmuxPaneId'
# → "%60"  ← use this for everything from here on
```

### 3. Launch the agent

```bash
tmux send-keys -t %60 'cd /absolute/path/to/repo && pi' Enter
# or for Claude:
tmux send-keys -t %60 'cd /absolute/path/to/repo && claude --model sonnet --permission-mode acceptEdits' Enter
```

**Model selection:**
- `haiku` — simple, fast tasks
- `sonnet` — normal tasks (default)
- `opus` — hard architectural or reasoning tasks

**Permission mode:**
- Default (no flag) — read/review only
- `--permission-mode acceptEdits` — agent needs to edit files

### 4. Wait for agent to be ready

Use `agentState` — it's agent-agnostic and reliable:

```bash
until [ "$(mori pane list --json | jq -r '.[] | select(.tmuxPaneId=="%60") | .agentState')" = "waitingForInput" ]; do sleep 3; done
```

Then do a visual check before sending:

```bash
tmux capture-pane -t %60 -p | tail -5
```

### 5. Send the request with reply instruction

Include a reply instruction so the helper pushes back when done. Define `mori_reply` in the helper's shell first (see [send-receive.md](send-receive.md)), then:

```bash
tmux send-keys -t %60 '[FROM:claude:%31 TO:pi:%60] Review plan.md. List top risks first, then suggest changes. When done, run: mori_reply "pi:%60" "%31" "<your summary>"' Enter
```

Verify it started processing (one-time check):

```bash
sleep 2 && tmux capture-pane -t %60 -p | tail -10
```

Then just wait — the helper will send back when ready.

### 6. Follow up or exit

```bash
# Follow-up (also with reply instruction)
tmux send-keys -t %60 '[FROM:claude:%31 TO:pi:%60] Now rewrite section 2. Reply back when done.' Enter

# Exit cleanly
tmux send-keys -t %60 '/exit' Enter
```

---

## Workflow B: Message an already-running agent

Use when the target pane already has a live agent.

### 1. Check agent state

```bash
mori pane list --json | jq '.[] | select(.tmuxPaneId=="%56") | {agentState, paneTitle}'
```

If `agentState` is `running`, read first before interrupting:

```bash
mori pane read --pane %56 --lines 60
```

### 2. Send with reply instruction

```bash
tmux send-keys -t %56 '[FROM:claude:%31 TO:pi:%56] UserDTO.role is now roles (string[]). Update your fetch calls. When done, run: mori_reply "pi:%56" "%31" "done"' Enter
```

The agent will push back when it finishes — you don't need to poll.

---

## Workflow C: Observe without interrupting

Use when you just need status or output from a pane.

```bash
# Via mori (preferred)
mori pane read --pane %56 --lines 80

# Via tmux (sanity check if mori output looks stale)
tmux capture-pane -t %56 -p | tail -30
```

Always prefer observe-only when you don't actually need to change the agent's behavior.
