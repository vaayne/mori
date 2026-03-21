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

## Ghostty Terminal

Ghostty keybindings that don't conflict with Mori shortcuts pass through
to the terminal. Common examples:

| Shortcut | Action |
|----------|--------|
| `⌘K` | Clear Screen |
| `⌘+` | Increase Font Size |
| `⌘-` | Decrease Font Size |

Customize terminal keybindings in `~/.config/ghostty/config`.
