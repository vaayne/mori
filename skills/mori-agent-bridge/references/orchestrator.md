# Multi-Agent Orchestration and Bidirectional Communication

## Bidirectional communication

Agents can send messages to each other using `tmux send-keys`. This was confirmed live:
- Claude sent to pi via `tmux send-keys -t %60`
- Pi sent back to Claude via `tmux send-keys -t %31`
- Claude received pi's message as normal user input

The mechanism is symmetric — any agent that can run shell commands can send to any other pane.

## Orchestrator pattern

One agent coordinates multiple workers. Dispatch tasks with reply instructions so workers push back when done — no polling required.

If helpers have `mori_reply` defined (see [send-receive.md](send-receive.md)):

```bash
tmux send-keys -t %60 '[FROM:claude:%31 TO:pi:%60] implement the caching layer in src/cache/. When done, run: mori_reply "pi:%60" "%31" "done: <summary>"' Enter
tmux send-keys -t %62 '[FROM:claude:%31 TO:codex:%62] update API docs in docs/api.md. When done, run: mori_reply "codex:%62" "%31" "done: <summary>"' Enter

# Workers push back when ready — orchestrator receives as normal input
```

If helpers do NOT have `mori_reply`, instruct them to run two separate commands:

```bash
# Tell the helper to run these two commands when done:
#   tmux send-keys -t %31 '[FROM:pi:%60 TO:claude:%31] done: <summary>'
#   tmux send-keys -t %31 Enter
# (Enter must be a standalone argument — not inside a quoted string)
```

## Peer-to-peer pattern

Two agents coordinate directly without an orchestrator. Each agent knows the other's pane ID.

```
Agent A (%31) ←→ Agent B (%60)

A sends: tmux send-keys -t %60 '[FROM:claude:%31 TO:pi:%60] I finished the API layer' Enter
B reads output, then replies (two-step):
  tmux send-keys -t %31 '[FROM:pi:%60 TO:claude:%31] ACK, starting integration tests'
  tmux send-keys -t %31 Enter
```

## Startup handshake

When launching a helper agent, have it announce its pane ID so the orchestrator has a verified handle:

```bash
# 1. Orchestrator launches helper in pane %60
tmux send-keys -t %60 'pi' Enter
sleep 3

# 2. Ask the helper to announce itself
tmux send-keys -t %60 'Run this shell command and tell me the output: echo MYID:$MORI_PANE_ID' Enter
sleep 5

# 3. Read the announcement
tmux capture-pane -t %60 -p | grep "MYID:"
# → MYID:%60

# 4. Now orchestrator has confirmed ID — use it for all future sends
```

## Agent registry

In a multi-agent session, maintain a simple registry as shell variables or a JSON file:

```bash
# Shell variable registry
ORCHESTRATOR_PANE="%31"
WORKER_PI_PANE="%60"
WORKER_CODEX_PANE="%62"

# Send with verified IDs
tmux send-keys -t "$WORKER_PI_PANE" "[FROM:claude:$ORCHESTRATOR_PANE TO:pi:$WORKER_PI_PANE] start task" Enter
```

## Push vs polling

Prefer **push**: include a reply instruction in every request so the helper agent sends back when done. The orchestrator just waits for input — no polling loop, no sleep heuristics.

Use **polling** only as a fallback when the helper agent cannot execute shell commands (e.g., a read-only observer):

```bash
until [ "$(mori pane list --json | jq -r '.[] | select(.tmuxPaneId=="%60") | .agentState')" = "waitingForInput" ]; do
  sleep 5
done
tmux capture-pane -t %60 -p | tail -30
```

## Model selection by task

| Task complexity | Model |
|---|---|
| Simple, fast check | `haiku` |
| Normal review or implementation | `sonnet` (default) |
| Hard architectural / deep reasoning | `opus` |

Always match model to task — don't use `opus` for trivial checks or `haiku` for deep work.
