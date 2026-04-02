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
            Focus.self,
            Send.self,
            NewWindow.self,
            Open.self,
            StatusCmd.self,
            PaneCmd.self,
        ]
    )
}

/// Resolve the Mori.app bundle URL relative to the CLI binary.
/// When bundled: .../Mori.app/Contents/MacOS/bin/mori
private func appBundleURL() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent() // bin/
        .deletingLastPathComponent() // MacOS/
        .deletingLastPathComponent() // Contents/
        .deletingLastPathComponent() // Mori.app/
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

// MARK: - IPC Helpers

/// Write a message to stderr.
private func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

/// Write a localized error to stderr and throw ExitCode.failure.
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

    // Poll for socket readiness (up to 10 seconds, check before sleeping)
    let maxAttempts = 20
    let intervalMicroseconds: useconds_t = 500_000 // 0.5s
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

    // 1. Relative to CLI binary (inside app bundle)
    let bundleCandidate = appBundleURL()
    if bundleCandidate.lastPathComponent == "Mori.app", isValidApp(bundleCandidate) {
        return bundleCandidate
    }

    // 2. /Applications/Mori.app
    let applicationsApp = URL(fileURLWithPath: "/Applications/Mori.app")
    if isValidApp(applicationsApp) { return applicationsApp }

    // 3. ~/Applications/Mori.app
    let homeApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Mori.app")
    if isValidApp(homeApps) { return homeApps }

    return nil
}

/// Print payload as raw JSON or using the given formatter.
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

/// Convenience for commands that return no structured data.
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

// MARK: - mori worktree

struct WorktreeCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: .localized("Manage git worktrees"),
        subcommands: [WorktreeCreate.self]
    )
}

struct WorktreeCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: .localized("Create a new worktree"),
        discussion: """
        \(String.localized("Creates a git worktree and a corresponding tmux session."))

        \(String.localized("Examples:"))
          mori worktree create myproject feature/auth
          mori worktree create myproject bugfix/login --json
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Branch name")))
    var branch: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.worktreeCreate(project: project, branch: branch))
        printResult(data, json: output.json, formatter: OutputFormat.formatWorktreeCreate)
    }
}

// MARK: - mori focus

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Focus a project and worktree"),
        discussion: """
        \(String.localized("Switches the Mori UI to show the specified project and worktree."))

        \(String.localized("Examples:"))
          mori focus myproject main
          mori focus myproject feature/auth
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.focus(project: project, worktree: worktree))
        printSuccess(data, json: output.json, label: String(format: .localized("Focused %@/%@"), project, worktree))
    }
}

// MARK: - mori send

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Send keys to a tmux window"),
        discussion: """
        \(String.localized("Keys use tmux send-keys syntax. Common keys: Enter, Escape, C-c (Ctrl+C), C-d, Space, Tab."))

        \(String.localized("Examples:"))
          mori send myproject main shell "echo hello Enter"
          mori send myproject main shell "C-c"
          mori send myproject main shell "mise run test Enter"
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Window name")))
    var window: String

    @Argument(help: ArgumentHelp(.localized("Keys to send (tmux send-keys syntax)")))
    var keys: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.send(project: project, worktree: worktree, window: window, keys: keys))
        printSuccess(data, json: output.json, label: String(format: .localized("Sent keys to %@/%@/%@"), project, worktree, window))
    }
}

// MARK: - mori new-window

struct NewWindow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-window",
        abstract: .localized("Create a new window in a worktree"),
        discussion: """
        \(String.localized("Creates a new tmux window (tab) in the worktree's session."))

        \(String.localized("Examples:"))
          mori new-window myproject main
          mori new-window myproject main --name logs
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Option(name: .long, help: ArgumentHelp(.localized("Window name (default: shell)")))
    var name: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.newWindow(project: project, worktree: worktree, name: name))
        printSuccess(data, json: output.json, label: String(format: .localized("Created window '%@' in %@/%@"), name ?? "shell", project, worktree))
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

// MARK: - mori status

struct StatusCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: .localized("Set workflow status for a worktree"),
        discussion: """
        \(String.localized("Workflow: todo → inProgress → needsReview → done / cancelled"))
        \(String.localized("Status is displayed as a badge in the Mori sidebar."))

        \(String.localized("Examples:"))
          mori status myproject feature/auth inProgress
          mori status myproject feature/auth done
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Workflow status (todo, inProgress, needsReview, done, cancelled)")))
    var status: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.setWorkflowStatus(project: project, worktree: worktree, status: status))
        printSuccess(data, json: output.json, label: String(format: .localized("Set %@/%@ status to '%@'"), project, worktree, status))
    }
}

// MARK: - mori pane

struct PaneCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: .localized("Pane commands for agent communication"),
        discussion: .localized("Enables agents to discover, observe, and interact with other panes."),
        subcommands: [PaneList.self, PaneRead.self, PaneMessage.self, PaneId.self]
    )
}

struct PaneList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List all panes with project/worktree/window info"),
        discussion: """
        \(String.localized("Shows all panes across projects with agent state and detected agent type."))

        \(String.localized("Examples:"))
          mori pane list
          mori pane list --project myproject
          mori pane list --project myproject --worktree main
        """
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Filter by project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Filter by worktree name")))
    var worktree: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.paneList(project: project, worktree: worktree))
        printResult(data, json: output.json, formatter: OutputFormat.formatPaneList)
    }
}

struct PaneRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: .localized("Capture output from a pane"),
        discussion: """
        \(String.localized("Reads recent terminal output from a pane without switching to it."))

        \(String.localized("Examples:"))
          mori pane read myproject main shell
          mori pane read myproject main logs --lines 100
        """
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Window name")))
    var window: String

    @Option(name: .long, help: ArgumentHelp(.localized("Number of lines to capture (1-200, default: 50)")))
    var lines: Int = 50

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.paneRead(project: project, worktree: worktree, window: window, lines: lines))
        // pane read returns plain text, not JSON — print as-is
        if let data, let text = String(data: data, encoding: .utf8) {
            print(text)
        }
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
          mori pane message myproject main shell "build completed"
          mori pane message myproject main editor "please review changes"
        """
    )

    @Argument(help: ArgumentHelp(.localized("Target project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Target worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Target window name")))
    var window: String

    @Argument(help: ArgumentHelp(.localized("Message text")))
    var text: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let senderProject = ProcessInfo.processInfo.environment["MORI_PROJECT"]
        let senderWorktree = ProcessInfo.processInfo.environment["MORI_WORKTREE"]
        let senderWindow = ProcessInfo.processInfo.environment["MORI_WINDOW"]
        let senderPaneId = ProcessInfo.processInfo.environment["MORI_PANE_ID"]

        let data = try sendIPCRequest(.paneMessage(
            project: project, worktree: worktree, window: window, text: text,
            senderProject: senderProject, senderWorktree: senderWorktree,
            senderWindow: senderWindow, senderPaneId: senderPaneId
        ))
        printSuccess(data, json: output.json, label: String(format: .localized("Message sent to %@/%@/%@"), project, worktree, window))
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
