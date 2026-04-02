import ArgumentParser
import Darwin
import Foundation
import MoriIPC

@main
struct MoriCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mori",
        abstract: .localized("Mori workspace CLI — communicate with the running Mori app."),
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

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: ArgumentHelp(.localized("Output raw JSON")))
    var json = false
}

// MARK: - IPC Helpers

/// Send an IPC request and return the response payload.
func sendIPCRequest(_ command: IPCCommand) throws -> Data? {
    switch diagnoseIPCSocket(at: IPCServer.defaultSocketPath) {
    case .missing:
        let message = String.localized("Mori app is not running. Launch Mori and try again.")
        FileHandle.standardError.write(Data(String.localized("Error: \(message)").utf8))
        throw ExitCode.failure
    case .stale:
        let message = String.localized("Mori app is not accepting CLI connections. Quit and relaunch Mori, then try again.")
        FileHandle.standardError.write(Data(String.localized("Error: \(message)").utf8))
        throw ExitCode.failure
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
        let errorMessage = String.localized("Error: \(message)")
        FileHandle.standardError.write(Data(errorMessage.utf8))
        throw ExitCode.failure
    }
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
        abstract: .localized("Project commands"),
        subcommands: [ProjectList.self]
    )
}

struct ProjectList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List all projects")
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
        abstract: .localized("Worktree commands"),
        subcommands: [WorktreeCreate.self]
    )
}

struct WorktreeCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: .localized("Create a new worktree")
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
        abstract: .localized("Focus a project and worktree")
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.focus(project: project, worktree: worktree))
        printResult(data, json: output.json, formatter: { _ in "" },
                    fallback: OutputFormat.formatSuccess(String(format: .localized("Focused %@/%@"), project, worktree)))
    }
}

// MARK: - mori send

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Send keys to a tmux window")
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Window name")))
    var window: String

    @Argument(help: ArgumentHelp(.localized("Keys to send")))
    var keys: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.send(project: project, worktree: worktree, window: window, keys: keys))
        printResult(data, json: output.json, formatter: { _ in "" },
                    fallback: OutputFormat.formatSuccess(String(format: .localized("Sent keys to %@/%@/%@"), project, worktree, window)))
    }
}

// MARK: - mori new-window

struct NewWindow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-window",
        abstract: .localized("Create a new window in a worktree")
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Option(name: .long, help: ArgumentHelp(.localized("Window name")))
    var name: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        let data = try sendIPCRequest(.newWindow(project: project, worktree: worktree, name: name))
        let label = name ?? "shell"
        printResult(data, json: output.json, formatter: { _ in "" },
                    fallback: OutputFormat.formatSuccess(String(format: .localized("Created window '%@' in %@/%@"), label, project, worktree)))
    }
}

// MARK: - mori open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Open a project from a path")
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
        discussion: .localized("Valid statuses: todo, inProgress, needsReview, done, cancelled")
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
        printResult(data, json: output.json, formatter: { _ in "" },
                    fallback: OutputFormat.formatSuccess(String(format: .localized("Set %@/%@ status to '%@'"), project, worktree, status)))
    }
}

// MARK: - mori pane

struct PaneCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: .localized("Pane commands for agent communication"),
        subcommands: [PaneList.self, PaneRead.self, PaneMessage.self, PaneId.self]
    )
}

struct PaneList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: .localized("List all panes with project/worktree/window info")
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Project name")))
    var project: String?

    @Option(name: .long, help: ArgumentHelp(.localized("Worktree name")))
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
        abstract: .localized("Capture output from a pane")
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Window name")))
    var window: String

    @Option(name: .long, help: ArgumentHelp(.localized("Number of lines to capture (default: 50, max: 200)")))
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
        abstract: .localized("Send a message to a pane with sender metadata")
    )

    @Argument(help: ArgumentHelp(.localized("Project name")))
    var project: String

    @Argument(help: ArgumentHelp(.localized("Worktree name")))
    var worktree: String

    @Argument(help: ArgumentHelp(.localized("Window name")))
    var window: String

    @Argument(help: ArgumentHelp(.localized("Message text")))
    var text: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        // Read sender identity from environment variables set by Mori in each pane
        let senderProject = ProcessInfo.processInfo.environment["MORI_PROJECT"]
        let senderWorktree = ProcessInfo.processInfo.environment["MORI_WORKTREE"]
        let senderWindow = ProcessInfo.processInfo.environment["MORI_WINDOW"]
        let senderPaneId = ProcessInfo.processInfo.environment["MORI_PANE_ID"]

        let data = try sendIPCRequest(.paneMessage(
            project: project, worktree: worktree, window: window, text: text,
            senderProject: senderProject, senderWorktree: senderWorktree,
            senderWindow: senderWindow, senderPaneId: senderPaneId
        ))
        printResult(data, json: output.json, formatter: { _ in "" },
                    fallback: OutputFormat.formatSuccess(String(format: .localized("Message sent to %@/%@/%@"), project, worktree, window)))
    }
}

struct PaneId: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "id",
        abstract: .localized("Print the current pane's identity")
    )

    func run() throws {
        // Read identity from environment variables set by Mori
        let project = ProcessInfo.processInfo.environment["MORI_PROJECT"] ?? "unknown"
        let worktree = ProcessInfo.processInfo.environment["MORI_WORKTREE"] ?? "unknown"
        let window = ProcessInfo.processInfo.environment["MORI_WINDOW"] ?? "unknown"
        let paneId = ProcessInfo.processInfo.environment["MORI_PANE_ID"] ?? "unknown"
        print("\(project)/\(worktree)/\(window) pane:\(paneId)")
    }
}
