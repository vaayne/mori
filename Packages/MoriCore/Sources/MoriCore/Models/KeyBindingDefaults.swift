import Foundation

/// All default key bindings for Mori.
public enum KeyBindingDefaults {

    /// The complete list of default bindings (configurable + locked).
    public static let all: [KeyBinding] = configurable + locked

    /// Returns defaults indexed by binding ID for quick lookup.
    public static let byId: [String: KeyBinding] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    // MARK: - Configurable Bindings

    public static let configurable: [KeyBinding] = [
        // Quick Jump (⌘1-9: context-aware, switches primary item in current sidebar mode)
        KeyBinding(id: "quickJump.goto1", displayNameKey: "keybinding.quickJump.goto1", category: .other,
                   shortcut: Shortcut(key: "1", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto2", displayNameKey: "keybinding.quickJump.goto2", category: .other,
                   shortcut: Shortcut(key: "2", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto3", displayNameKey: "keybinding.quickJump.goto3", category: .other,
                   shortcut: Shortcut(key: "3", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto4", displayNameKey: "keybinding.quickJump.goto4", category: .other,
                   shortcut: Shortcut(key: "4", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto5", displayNameKey: "keybinding.quickJump.goto5", category: .other,
                   shortcut: Shortcut(key: "5", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto6", displayNameKey: "keybinding.quickJump.goto6", category: .other,
                   shortcut: Shortcut(key: "6", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto7", displayNameKey: "keybinding.quickJump.goto7", category: .other,
                   shortcut: Shortcut(key: "7", modifiers: .cmd)),
        KeyBinding(id: "quickJump.goto8", displayNameKey: "keybinding.quickJump.goto8", category: .other,
                   shortcut: Shortcut(key: "8", modifiers: .cmd)),
        KeyBinding(id: "quickJump.gotoLast", displayNameKey: "keybinding.quickJump.gotoLast", category: .other,
                   shortcut: Shortcut(key: "9", modifiers: .cmd)),

        // Tabs
        KeyBinding(id: "tabs.newTab", displayNameKey: "keybinding.tabs.newTab", category: .tabs,
                   shortcut: Shortcut(key: "t", modifiers: .cmd)),
        KeyBinding(id: "tabs.closeTab", displayNameKey: "keybinding.tabs.closeTab", category: .tabs,
                   shortcut: Shortcut(key: "w", modifiers: .cmd)),
        KeyBinding(id: "tabs.nextTab", displayNameKey: "keybinding.tabs.nextTab", category: .tabs,
                   shortcut: Shortcut(key: "]", modifiers: .cmdShift)),
        KeyBinding(id: "tabs.previousTab", displayNameKey: "keybinding.tabs.previousTab", category: .tabs,
                   shortcut: Shortcut(key: "[", modifiers: .cmdShift)),

        // Panes
        KeyBinding(id: "panes.splitRight", displayNameKey: "keybinding.panes.splitRight", category: .panes,
                   shortcut: Shortcut(key: "d", modifiers: .cmd)),
        KeyBinding(id: "panes.splitDown", displayNameKey: "keybinding.panes.splitDown", category: .panes,
                   shortcut: Shortcut(key: "d", modifiers: .cmdShift)),
        KeyBinding(id: "panes.nextPane", displayNameKey: "keybinding.panes.nextPane", category: .panes,
                   shortcut: Shortcut(key: "]", modifiers: .cmd)),
        KeyBinding(id: "panes.previousPane", displayNameKey: "keybinding.panes.previousPane", category: .panes,
                   shortcut: Shortcut(key: "[", modifiers: .cmd)),
        KeyBinding(id: "panes.navUp", displayNameKey: "keybinding.panes.navUp", category: .panes,
                   shortcut: Shortcut(key: "↑", keyCode: 126, modifiers: .cmdOption)),
        KeyBinding(id: "panes.navDown", displayNameKey: "keybinding.panes.navDown", category: .panes,
                   shortcut: Shortcut(key: "↓", keyCode: 125, modifiers: .cmdOption)),
        KeyBinding(id: "panes.navLeft", displayNameKey: "keybinding.panes.navLeft", category: .panes,
                   shortcut: Shortcut(key: "←", keyCode: 123, modifiers: .cmdOption)),
        KeyBinding(id: "panes.navRight", displayNameKey: "keybinding.panes.navRight", category: .panes,
                   shortcut: Shortcut(key: "→", keyCode: 124, modifiers: .cmdOption)),
        KeyBinding(id: "panes.resizeUp", displayNameKey: "keybinding.panes.resizeUp", category: .panes,
                   shortcut: Shortcut(key: "↑", keyCode: 126, modifiers: .cmdControl)),
        KeyBinding(id: "panes.resizeDown", displayNameKey: "keybinding.panes.resizeDown", category: .panes,
                   shortcut: Shortcut(key: "↓", keyCode: 125, modifiers: .cmdControl)),
        KeyBinding(id: "panes.resizeLeft", displayNameKey: "keybinding.panes.resizeLeft", category: .panes,
                   shortcut: Shortcut(key: "←", keyCode: 123, modifiers: .cmdControl)),
        KeyBinding(id: "panes.resizeRight", displayNameKey: "keybinding.panes.resizeRight", category: .panes,
                   shortcut: Shortcut(key: "→", keyCode: 124, modifiers: .cmdControl)),
        KeyBinding(id: "panes.equalize", displayNameKey: "keybinding.panes.equalize", category: .panes,
                   shortcut: Shortcut(key: "=", modifiers: .cmdControl)),
        KeyBinding(id: "panes.toggleZoom", displayNameKey: "keybinding.panes.toggleZoom", category: .panes,
                   shortcut: Shortcut(key: "↩", keyCode: 36, modifiers: .cmdShift)),

        // Tools
        KeyBinding(id: "tools.lazygit", displayNameKey: "keybinding.tools.lazygit", category: .tools,
                   shortcut: Shortcut(key: "g", modifiers: .cmd)),
        KeyBinding(id: "tools.yazi", displayNameKey: "keybinding.tools.yazi", category: .tools,
                   shortcut: Shortcut(key: "e", modifiers: .cmd)),

        // Window
        KeyBinding(id: "window.toggleSidebar", displayNameKey: "keybinding.window.toggleSidebar", category: .window,
                   shortcut: Shortcut(key: "b", modifiers: .cmd)),
        KeyBinding(id: "window.closeWindow", displayNameKey: "keybinding.window.closeWindow", category: .window,
                   shortcut: Shortcut(key: "w", modifiers: .cmdShift)),

        // Worktrees
        KeyBinding(id: "worktrees.create", displayNameKey: "keybinding.worktrees.create", category: .worktrees,
                   shortcut: Shortcut(key: "n", modifiers: .cmdShift)),
        KeyBinding(id: "worktrees.cycleNext", displayNameKey: "keybinding.worktrees.cycleNext", category: .worktrees,
                   shortcut: Shortcut(key: "(tab)", keyCode: 48, modifiers: .ctrl)),
        KeyBinding(id: "worktrees.cyclePrevious", displayNameKey: "keybinding.worktrees.cyclePrevious", category: .worktrees,
                   shortcut: Shortcut(key: "(tab)", keyCode: 48, modifiers: .ctrlShift)),

        // Settings
        KeyBinding(id: "settings.open", displayNameKey: "keybinding.settings.open", category: .settings,
                   shortcut: Shortcut(key: ",", modifiers: .cmd)),
        KeyBinding(id: "settings.reload", displayNameKey: "keybinding.settings.reload", category: .settings,
                   shortcut: Shortcut(key: ",", modifiers: .cmdShift)),

        // Other
        KeyBinding(id: "other.openProject", displayNameKey: "keybinding.other.openProject", category: .other,
                   shortcut: Shortcut(key: "o", modifiers: .cmdShift)),
        KeyBinding(id: "other.agentDashboard", displayNameKey: "keybinding.other.agentDashboard", category: .other,
                   shortcut: Shortcut(key: "a", modifiers: .cmdShift)),
        KeyBinding(id: "commandPalette.toggle", displayNameKey: "keybinding.commandPalette.toggle", category: .other,
                   shortcut: Shortcut(key: "p", modifiers: .cmdShift)),
        KeyBinding(id: "other.projectSwitcher", displayNameKey: "keybinding.other.projectSwitcher", category: .other,
                   shortcut: Shortcut(key: "p", modifiers: .cmd)),
    ]

    // MARK: - Locked (System) Bindings

    public static let locked: [KeyBinding] = [
        KeyBinding(id: "system.undo", displayNameKey: "keybinding.system.undo", category: .system,
                   shortcut: Shortcut(key: "z", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.redo", displayNameKey: "keybinding.system.redo", category: .system,
                   shortcut: Shortcut(key: "z", modifiers: .cmdShift), isLocked: true),
        KeyBinding(id: "system.cut", displayNameKey: "keybinding.system.cut", category: .system,
                   shortcut: Shortcut(key: "x", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.copy", displayNameKey: "keybinding.system.copy", category: .system,
                   shortcut: Shortcut(key: "c", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.paste", displayNameKey: "keybinding.system.paste", category: .system,
                   shortcut: Shortcut(key: "v", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.selectAll", displayNameKey: "keybinding.system.selectAll", category: .system,
                   shortcut: Shortcut(key: "a", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.hide", displayNameKey: "keybinding.system.hide", category: .system,
                   shortcut: Shortcut(key: "h", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.hideOthers", displayNameKey: "keybinding.system.hideOthers", category: .system,
                   shortcut: Shortcut(key: "h", modifiers: .cmdOption), isLocked: true),
        KeyBinding(id: "system.quit", displayNameKey: "keybinding.system.quit", category: .system,
                   shortcut: Shortcut(key: "q", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.minimize", displayNameKey: "keybinding.system.minimize", category: .system,
                   shortcut: Shortcut(key: "m", modifiers: .cmd), isLocked: true),
        KeyBinding(id: "system.toggleFullScreen", displayNameKey: "keybinding.system.toggleFullScreen", category: .system,
                   shortcut: Shortcut(key: "f", modifiers: .cmdControl), isLocked: true),
    ]
}
