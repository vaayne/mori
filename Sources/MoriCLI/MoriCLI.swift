import ArgumentParser
import Darwin
import Foundation
import MoriIPC

@main
struct MoriCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mori",
        abstract: .localized("Mori workspace CLI — communicate with the running Mori app."),
        discussion: """
        \(String.localized("Communicates with Mori.app via Unix socket. Launches the app automatically if not running."))
        \(String.localized("All subcommands accept --json for machine-readable output."))

        \(String.localized("Shell completions:"))
          mori --generate-completion-script zsh
          mori --generate-completion-script bash
          mori --generate-completion-script fish
        """,
        version: cliVersion(),
        subcommands: [
            Project.self,
            WorktreeCmd.self,
            WindowCmd.self,
            PaneCmd.self,
            Focus.self,
            Open.self,
        ]
    )
}

/// Resolve the Mori.app bundle URL relative to the CLI binary.
/// When bundled: .../Mori.app/Contents/MacOS/bin/mori
private func appBundleURL() -> URL {
    let argv0 = CommandLine.arguments[0]
    let execURL: URL
    if argv0.hasPrefix("/") {
        execURL = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
    } else if let resolved = resolveExecutableInPATH(argv0) {
        execURL = resolved
    } else {
        execURL = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
    }
    return execURL
        .deletingLastPathComponent() // bin/
        .deletingLastPathComponent() // MacOS/
        .deletingLastPathComponent() // Contents/
        .deletingLastPathComponent() // Mori.app/
}

private func resolveExecutableInPATH(_ name: String) -> URL? {
    let fm = FileManager.default
    if name.contains("/") {
        let url = URL(fileURLWithPath: name).resolvingSymlinksInPath()
        return fm.fileExists(atPath: url.path) ? url : nil
    }
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
    for dir in pathEnv.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
        if fm.isExecutableFile(atPath: candidate.path) {
            return candidate.resolvingSymlinksInPath()
        }
    }
    return nil
}

private func cliVersion() -> String {
    let plistURL = appBundleURL().appendingPathComponent("Contents/Info.plist")
    if let data = try? Data(contentsOf: plistURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
       let version = plist["CFBundleShortVersionString"] as? String {
        return version
    }
    return "dev"
}

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: ArgumentHelp(.localized("Output as JSON (default: human-readable)")))
    var json = false
}

// MARK: - Address Resolution

enum CLIError: Error, CustomStringConvertible {
    case missingAddress(label: String, envKey: String)
    var description: String {
        switch self {
        case .missingAddress(let label, let envKey):
            return "\(label) not specified. Pass --\(label) or set \(envKey)."
        }
    }
}

func resolveRequired(_ flag: String?, envKey: String, label: String) throws -> String {
    if let v = flag { return v }
    if let v = ProcessInfo.processInfo.environment[envKey] { return v }
    throw CLIError.missingAddress(label: label, envKey: envKey)
}

func resolveOptional(_ flag: String?, envKey: String) -> String? {
    flag ?? ProcessInfo.processInfo.environment[envKey]
}

// MARK: - IPC Helpers

private func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private func exitWithError(_ message: String) throws -> Never {
    writeStderr(String.localized("Error: \(message)"))
    throw ExitCode.failure
}

/// Send an IPC request and return the response payload.
/// Auto-launches Mori.app if not running.
func sendIPCRequest(_ command: IPCCommand) throws -> Data? {
    let socketPath = IPCServer.defaultSocketPath

    switch diagnoseIPCSocket(at: socketPath) {
    case .missing, .stale:
        try launchMoriAppAndWait(socketPath: socketPath)
    case .ready, .indeterminate:
        break
    }

    let client = IPCClient()
    let request = IPCRequest(command: command, requestId: UUID().uuidString)
    let envelope = try client.sendSync(request)

    switch envelope.response {
    case .success(let payload):
        return payload
    case .error(let message):
        try exitWithError(message)
    }
}

// MARK: - App Launcher

private func launchMoriAppAndWait(socketPath: String) throws {
    guard let appURL = findMoriApp() else {
        try exitWithError(.localized("Mori.app not found. Install Mori and try again."))
    }

    writeStderr(String.localized("Launching Mori.app…\n"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", appURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        try exitWithError(.localized("Failed to launch Mori.app."))
    }

    let maxAttempts = 20
    let intervalMicroseconds: useconds_t = 500_000
    for _ in 0..<maxAttempts {
        if case .ready = diagnoseIPCSocket(at: socketPath) { return }
        usleep(intervalMicroseconds)
    }

    try exitWithError(.localized("Mori.app launched but IPC socket not ready after 10s."))
}

private func findMoriApp() -> URL? {
    let fm = FileManager.default
    func isValidApp(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/Mori").path)
    }

    let bundleCandidate = appBundleURL()
    if bundleCandidate.lastPathComponent == "Mori.app", isValidApp(bundleCandidate) {
        return bundleCandidate
    }

    let applicationsApp = URL(fileURLWithPath: "/Applications/Mori.app")
    if isValidApp(applicationsApp) { return applicationsApp }

    let homeApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Mori.app")
    if isValidApp(homeApps) { return homeApps }

    return nil
}

func printResult(_ data: Data?, json: Bool, formatter: (Data) -> String, fallback: String = "✓ OK") {
    guard let data else {
        if json {
            print("{\"status\":\"ok\"}")
        } else {
            print(fallback)
        }
        return
    }
    if json {
        print(OutputFormat.prettyJSON(data))
    } else {
        print(formatter(data))
    }
}

func printSuccess(_ data: Data?, json: Bool, label: String) {
    printResult(data, json: json, formatter: { _ in "" }, fallback: "✓ \(label)")
}

private enum IPCSocketStatus {
    case ready
    case missing
    case stale
    case indeterminate
}

private func diagnoseIPCSocket(at path: String) -> IPCSocketStatus {
    guard FileManager.default.fileExists(atPath: path) else {
        return .missing
    }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        return .indeterminate
    }
    defer { close(fd) }

    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
    address.sun_family = sa_family_t(AF_UNIX)

    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < maxPathLength else {
        return .indeterminate
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        _ = pathBytes.withUnsafeBytes { src in
            memcpy(buffer.baseAddress, src.baseAddress, src.count)
        }
    }

    let didConnect = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.stride))
        }
    }

    if didConnect == 0 {
        return .ready
    }

    switch errno {
    case ENOENT:
        return .missing
    case ECONNREFUSED:
        return .stale
    default:
        return .indeterminate
    }
}

// MARK: - mori project

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Manage Mori projects"),
        subcommands: [ProjectList.self]
    )
}

struct ProjectList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List all projects"),
        discussion: """
        \(String.localized("Shows all projects tracked by Mori with their names and paths."))

        \(String.localized("Examples:"))
          mori project list
          mori project list --json
        """
    )

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.projectList)
        printResult(data, json: output.json, formatter: OutputFormat.formatProjectList)
    }
}

// MARK: - mori open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Open a project from a path"),
        discussion: """
        \(String.localized("Opens an existing project or creates a new one from the directory. Use '.' for the current directory."))

        \(String.localized("Examples:"))
          mori open .
          mori open ~/workspace/myproject
        """
    )

    @Argument(help: ArgumentHelp(.localized("Path to project directory")))
    var path: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.open(path: path))
        printResult(data, json: output.json, formatter: OutputFormat.formatProjectOpen)
    }
}

// MARK: - mori worktree

struct WorktreeCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: .localized("Manage git worktrees"),
        subcommands: [WorktreeList.self, WorktreeNew.self, WorktreeDelete.self]
    )
}

struct WorktreeList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List worktrees for a project"),
        discussion: """
        \(String.localized("Examples:"))
          mori worktree list --project myapp
          mori worktree list   # uses MORI_PROJECT env var
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let data = try sendIPCRequest(.worktreeList(project: proj))
        printResult(data, json: output.json, formatter: OutputFormat.formatWorktreeList)
    }
}

struct WorktreeNew: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: .localized("Create a new worktree"),
        discussion: """
        \(String.localized("Creates a git worktree and a corresponding tmux session."))

        \(String.localized("Examples:"))
          mori worktree new feature/auth --project myapp
          mori worktree new feature/auth   # uses MORI_PROJECT
        """
    )

    @Argument(help: ArgumentHelp(.localized("Branch name")))
    var branch: String

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let data = try sendIPCRequest(.worktreeCreate(project: proj, branch: branch))
        printResult(data, json: output.json, formatter: OutputFormat.formatWorktreeCreate)
    }
}

struct WorktreeDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: .localized("Delete a worktree"),
        discussion: """
        \(String.localized("Kills the tmux session and removes the git worktree. The main worktree cannot be deleted."))

        \(String.localized("Examples:"))
          mori worktree delete --project myapp --worktree feat/auth
          mori worktree delete   # uses MORI_PROJECT and MORI_WORKTREE
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let data = try sendIPCRequest(.worktreeDelete(project: proj, worktree: wt))
        printSuccess(data, json: output.json, label: String(format: .localized("Deleted worktree '%@'"), wt))
    }
}

// MARK: - mori window

struct WindowCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: .localized("Manage tmux windows"),
        subcommands: [WindowList.self, WindowNew.self, WindowRename.self, WindowClose.self]
    )
}

struct WindowList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List windows in a worktree"),
        discussion: """
        \(String.localized("Examples:"))
          mori window list --project myapp --worktree main
          mori window list   # uses MORI_PROJECT and MORI_WORKTREE
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let data = try sendIPCRequest(.windowList(project: proj, worktree: wt))
        printResult(data, json: output.json, formatter: OutputFormat.formatWindowList)
    }
}

struct WindowNew: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: .localized("Create a new window"),
        discussion: """
        \(String.localized("Creates a new tmux window (tab) in the worktree's session."))

        \(String.localized("Examples:"))
          mori window new --name logs
          mori window new --project myapp --worktree main --name tests
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name (default: shell)")))
    var name: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let data = try sendIPCRequest(.windowNew(project: proj, worktree: wt, name: name))
        printSuccess(data, json: output.json, label: String(format: .localized("Created window '%@' in %@/%@"), name ?? "shell", proj, wt))
    }
}

struct WindowRename: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: .localized("Rename a window"),
        discussion: """
        \(String.localized("Examples:"))
          mori window rename terminal
          mori window rename terminal --window shell
        """
    )

    @Argument(help: ArgumentHelp(.localized("New window name")))
    var newName: String

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let data = try sendIPCRequest(.windowRename(project: proj, worktree: wt, window: win, newName: newName))
        printSuccess(data, json: output.json, label: String(format: .localized("Renamed window '%@' → '%@'"), win, newName))
    }
}

struct WindowClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: .localized("Close a window"),
        discussion: """
        \(String.localized("Examples:"))
          mori window close
          mori window close --window logs
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let data = try sendIPCRequest(.windowClose(project: proj, worktree: wt, window: win))
        printSuccess(data, json: output.json, label: String(format: .localized("Closed window '%@'"), win))
    }
}

// MARK: - mori pane

struct PaneCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: .localized("Pane commands for agent communication"),
        discussion: .localized("Enables agents to discover, observe, and interact with other panes."),
        subcommands: [PaneList.self, PaneNew.self, PaneSend.self, PaneRead.self, PaneRename.self, PaneClose.self, PaneMessage.self, PaneId.self]
    )
}

struct PaneList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List panes"),
        discussion: """
        \(String.localized("Inside a Mori terminal: scopes to the current window by default."))
        \(String.localized("No env vars and no flags: shows all panes across all projects."))

        \(String.localized("Examples:"))
          mori pane list
          mori pane list --project myapp --worktree main --window shell
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Filter by project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Filter by worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Filter by window name")))
    var window: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = resolveOptional(project, envKey: "MORI_PROJECT")
        let wt = resolveOptional(worktree, envKey: "MORI_WORKTREE")
        let win = resolveOptional(window, envKey: "MORI_WINDOW")
        let data = try sendIPCRequest(.paneList(project: proj, worktree: wt, window: win))
        printResult(data, json: output.json, formatter: OutputFormat.formatPaneList)
    }
}

struct PaneNew: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: .localized("Split a new pane"),
        discussion: """
        \(String.localized("Examples:"))
          mori pane new
          mori pane new --split v --name agent
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Split direction: h (horizontal) or v (vertical, default: h)")))
    var split: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Pane title")))
    var name: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let data = try sendIPCRequest(.paneNew(project: proj, worktree: wt, window: win, split: split, name: name))
        printResult(data, json: output.json, formatter: OutputFormat.formatPaneNew)
    }
}

struct PaneSend: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: .localized("Send keys to a pane"),
        discussion: """
        \(String.localized("Keys use tmux send-keys syntax. Common keys: Enter, Escape, C-c (Ctrl+C), C-d, Space, Tab."))

        \(String.localized("Examples:"))
          mori pane send "npm test Enter"
          mori pane send --window logs "q"
          mori pane send --pane %5 "C-c"
        """
    )

    @Argument(help: ArgumentHelp(.localized("Keys to send (tmux send-keys syntax)")))
    var keys: String

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Pane ID (e.g. %3); defaults to active pane")))
    var pane: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        // Only inherit MORI_PANE_ID when the window is also from the env (not overridden).
        // An explicit --window means we're targeting a different window, so MORI_PANE_ID
        // (which belongs to the current window) must not carry over.
        let paneId: String?
        if pane != nil {
            paneId = pane
        } else if window == nil {
            paneId = resolveOptional(nil, envKey: "MORI_PANE_ID")
        } else {
            paneId = nil
        }
        let data = try sendIPCRequest(.paneSend(project: proj, worktree: wt, window: win, pane: paneId, keys: keys))
        printSuccess(data, json: output.json, label: String(format: .localized("Sent keys to %@/%@/%@"), proj, wt, win))
    }
}

struct PaneRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: .localized("Capture output from a pane"),
        discussion: """
        \(String.localized("Reads recent terminal output from a pane without switching to it."))

        \(String.localized("Examples:"))
          mori pane read
          mori pane read --lines 200
          mori pane read --pane %4
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Pane ID (e.g. %3); defaults to active pane")))
    var pane: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Number of lines to capture (1-200, default: 50)")))
    var lines: Int = 50

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let paneId = resolveOptional(pane, envKey: "MORI_PANE_ID")
        let data = try sendIPCRequest(.paneRead(project: proj, worktree: wt, window: win, pane: paneId, lines: lines))
        guard let data, let text = String(data: data, encoding: .utf8) else { return }
        if output.json {
            let envelope = ["output": text]
            if let jsonData = try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            }
        } else {
            print(text)
        }
    }
}

struct PaneRename: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: .localized("Rename a pane"),
        discussion: """
        \(String.localized("Examples:"))
          mori pane rename agent
          mori pane rename agent --pane %3
        """
    )

    @Argument(help: ArgumentHelp(.localized("New pane title")))
    var newName: String

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Pane ID (e.g. %3); defaults to MORI_PANE_ID")))
    var pane: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let paneId = try resolveRequired(pane, envKey: "MORI_PANE_ID", label: "pane")
        let data = try sendIPCRequest(.paneRename(project: proj, worktree: wt, window: win, pane: paneId, newName: newName))
        printSuccess(data, json: output.json, label: String(format: .localized("Renamed pane %@ → '%@'"), paneId, newName))
    }
}

struct PaneClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: .localized("Close a pane"),
        discussion: """
        \(String.localized("Examples:"))
          mori pane close
          mori pane close --pane %3
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Pane ID (e.g. %3); defaults to active pane")))
    var pane: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")
        let paneId = resolveOptional(pane, envKey: "MORI_PANE_ID")
        let data = try sendIPCRequest(.paneClose(project: proj, worktree: wt, window: win, pane: paneId))
        printSuccess(data, json: output.json, label: String(format: .localized("Closed pane %@"), paneId ?? .localized("active")))
    }
}

struct PaneMessage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "message",
        abstract: .localized("Send a message to a pane with sender metadata"),
        discussion: """
        \(String.localized("Sends a message to another pane for inter-agent communication."))
        \(String.localized("Sender identity is read from MORI_PROJECT, MORI_WORKTREE, MORI_WINDOW, MORI_PANE_ID environment variables (set automatically in Mori terminals)."))

        \(String.localized("Examples:"))
          mori pane message "build completed"
          mori pane message --project myapp --worktree main --window editor "please review changes"
        """
    )

    @Argument(help: ArgumentHelp(.localized("Message text")))
    var text: String

    @Option(name: .long, help: ArgumentHelp(.localized("Target project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Target worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Target window name")))
    var window: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let wt = try resolveRequired(worktree, envKey: "MORI_WORKTREE", label: "worktree")
        let win = try resolveRequired(window, envKey: "MORI_WINDOW", label: "window")

        let senderProject = ProcessInfo.processInfo.environment["MORI_PROJECT"]
        let senderWorktree = ProcessInfo.processInfo.environment["MORI_WORKTREE"]
        let senderWindow = ProcessInfo.processInfo.environment["MORI_WINDOW"]
        let senderPaneId = ProcessInfo.processInfo.environment["MORI_PANE_ID"]

        let data = try sendIPCRequest(.paneMessage(
            project: proj, worktree: wt, window: win, text: text,
            senderProject: senderProject, senderWorktree: senderWorktree,
            senderWindow: senderWindow, senderPaneId: senderPaneId
        ))
        printSuccess(data, json: output.json, label: String(format: .localized("Message sent to %@/%@/%@"), proj, wt, win))
    }
}

struct PaneId: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "id",
        abstract: .localized("Print the current pane's identity"),
        discussion: """
        \(String.localized("Reads MORI_* environment variables to identify the current pane. Does not require Mori.app to be running."))

        \(String.localized("Examples:"))
          mori pane id
        """
    )

    func run() throws {
        let project = ProcessInfo.processInfo.environment["MORI_PROJECT"] ?? "unknown"
        let worktree = ProcessInfo.processInfo.environment["MORI_WORKTREE"] ?? "unknown"
        let window = ProcessInfo.processInfo.environment["MORI_WINDOW"] ?? "unknown"
        let paneId = ProcessInfo.processInfo.environment["MORI_PANE_ID"] ?? "unknown"
        print("\(project)/\(worktree)/\(window) pane:\(paneId)")
    }
}

// MARK: - mori focus

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Focus a project, worktree, or window in the Mori UI"),
        discussion: """
        \(String.localized("Behavior:"))
          --project only           → focus the project's last active worktree
          --project --worktree     → focus the worktree
          all three                → focus the specific window

        \(String.localized("Examples:"))
          mori focus --project myapp
          mori focus --project myapp --worktree feat/auth
          mori focus --window logs
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var window: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let proj = try resolveRequired(project, envKey: "MORI_PROJECT", label: "project")
        let resolvedWorktree = resolveOptional(worktree, envKey: "MORI_WORKTREE")
        let resolvedWindow = resolveOptional(window, envKey: "MORI_WINDOW")

        if let wt = resolvedWorktree, let win = resolvedWindow {
            let data = try sendIPCRequest(.focusWindow(project: proj, worktree: wt, window: win))
            printSuccess(data, json: output.json, label: String(format: .localized("Focused %@/%@/%@"), proj, wt, win))
        } else if let wt = resolvedWorktree {
            let data = try sendIPCRequest(.focus(project: proj, worktree: wt))
            printSuccess(data, json: output.json, label: String(format: .localized("Focused %@/%@"), proj, wt))
        } else {
            let data = try sendIPCRequest(.focusProject(project: proj))
            printSuccess(data, json: output.json, label: String(format: .localized("Focused %@"), proj))
        }
    }
}
