# Agent-Aware Tabs & Notifications (Simplified)

## Overview

Detect coding agents in tmux panes, auto-rename tabs, send rich notifications. Zero config — uses existing 5s tmux polling.

**Branch:** `feature/agent-aware-tabs`

## Phases

### Phase 1: AgentDetector (MoriTmux) — 2 tasks

| # | Task | File | Status |
|---|------|------|--------|
| 1.1 | Create `AgentDetector` — process matching + agent-specific output patterns | `MoriTmux/AgentDetector.swift` (NEW) | ⬜ |
| 1.2 | Tests | `MoriTmuxTests/main.swift` | ⬜ |

### Phase 2: Tab Naming + Detection Integration (App Target) — 3 tasks

| # | Task | File | Status |
|---|------|------|--------|
| 2.1 | Add `detectedAgent: String?` to `RuntimeWindow` | `MoriCore/Models/RuntimeWindow.swift` | ⬜ |
| 2.2 | Create `AgentTabNamer` — rename/restore + emoji mapping | `Sources/Mori/App/AgentTabNamer.swift` (NEW) | ⬜ |
| 2.3 | Wire into `WorkspaceManager.detectAgentStates()` — auto-detect agents in ALL windows, auto-tag, rename | `Sources/Mori/App/WorkspaceManager.swift` | ⬜ |

### Phase 3: Enhanced Notifications — 2 tasks

| # | Task | File | Status |
|---|------|------|--------|
| 3.1 | Enrich notification content with agent name | `Sources/Mori/App/NotificationManager.swift` | ⬜ |
| 3.2 | Pass `detectedAgent` through `checkNotifications()` | `Sources/Mori/App/WorkspaceManager.swift` | ⬜ |

## Total: 7 tasks
