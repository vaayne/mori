# Mori Keymaps

Mori uses tmux as its session backend. Keyboard shortcuts manage tmux sessions,
windows (tabs), and panes through a native macOS interface.

## App

| Shortcut | Action |
|----------|--------|
| `⌘⇧O` | Open Project |
| `⌘,` | Settings (opens ghostty config) |
| `⌘⇧,` | Reload Settings |
| `⌘H` | Hide Mori |
| `⌘⌥H` | Hide Others |
| `⌘Q` | Quit Mori |

## Edit

| Shortcut | Action |
|----------|--------|
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘X` | Cut |
| `⌘C` | Copy |
| `⌘V` | Paste |
| `⌘A` | Select All |

## Tabs (tmux windows)

| Shortcut | Action |
|----------|--------|
| `⌘T` | New Tab |
| `⌘W` | Close Pane (last pane closes the tab) |
| `⌘⇧]` | Next Tab |
| `⌘⇧[` | Previous Tab |
| `⌘1`–`⌘9` | Go to Tab 1–9 (`⌘9` = last) |

## Panes (tmux panes)

| Shortcut | Action |
|----------|--------|
| `⌘D` | Split Right |
| `⌘⇧D` | Split Down |
| `⌘]` | Next Pane (cycle) |
| `⌘[` | Previous Pane (cycle) |
| `⌘⌥↑` | Go to Pane Above |
| `⌘⌥↓` | Go to Pane Below |
| `⌘⌥←` | Go to Pane Left |
| `⌘⌥→` | Go to Pane Right |
| `⌘⌃↑` | Resize Pane Up |
| `⌘⌃↓` | Resize Pane Down |
| `⌘⌃←` | Resize Pane Left |
| `⌘⌃→` | Resize Pane Right |
| `⌘⇧↩` | Toggle Pane Zoom |
| `⌘⌃=` | Equalize Panes |

## Tools

| Shortcut | Action |
|----------|--------|
| `⌘G` | Open Lazygit |
| `⌘E` | Open Yazi |

## Window

| Shortcut | Action |
|----------|--------|
| `⌘B` | Toggle Sidebar |
| `⌘⌃F` | Toggle Full Screen |
| `⌘M` | Minimize |
| `⌘⇧W` | Close Window |

## Worktrees

| Shortcut | Action |
|----------|--------|
| `⌘⇧N` | New Worktree |
| `⌃Tab` | Next Worktree |
| `⌃⇧Tab` | Previous Worktree |

## Command Palette

| Shortcut | Action |
|----------|--------|
| `⌘⇧P` | Toggle Command Palette |

## Customizing Shortcuts

All Mori app shortcuts listed above (except locked system shortcuts) are fully
customizable via **Settings > Keyboard**. You can remap any configurable shortcut
to a different key combination, unassign it entirely, or reset it back to the
default.

Locked shortcuts — such as Edit commands (Cmd+Z, Cmd+C, etc.), Quit (Cmd+Q),
Hide (Cmd+H), Minimize (Cmd+M), and Toggle Fullscreen (Cmd+Ctrl+F) — cannot be
changed because they are routed through the macOS AppKit responder chain.

Mori includes conflict detection: if you assign a shortcut that is already used
by a locked system binding, the assignment is blocked. If the conflict is with
another configurable binding, Mori warns you and offers to reassign, displacing
the previous binding. To restore all shortcuts to their original defaults, use
the **Reset All** button in Settings > Keyboard.

Shortcut overrides are saved to `~/Library/Application Support/Mori/keybindings.json`
as a sparse file (only modified bindings are stored). Changes take effect
immediately without restarting the app.

> **Note:** Ghostty terminal keybindings are configured separately — see the
> section below.

## Ghostty Terminal

Ghostty keybindings that don't conflict with Mori shortcuts pass through
to the terminal. Common examples:

| Shortcut | Action |
|----------|--------|
| `⌘K` | Clear Screen |
| `⌘+` | Increase Font Size |
| `⌘-` | Decrease Font Size |

Customize terminal keybindings in `~/.config/ghostty/config`.
