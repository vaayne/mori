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
        ]
    )
}

// MARK: - Shared Helpers

/// Send an IPC request and print the result as JSON.
func runIPCRequest(_ command: IPCCommand) throws {
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
        if let data = payload, let json = String(data: data, encoding: .utf8) {
            print(json)
        } else {
            print("{\"status\":\"ok\"}")
        }
    case .error(let message):
        let errorMessage = String.localized("Error: \(message)")
        FileHandle.standardError.write(Data(errorMessage.utf8))
        throw ExitCode.failure
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

    func run() throws {
        try runIPCRequest(.projectList)
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

    func run() throws {
        try runIPCRequest(.worktreeCreate(project: project, branch: branch))
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

    func run() throws {
        try runIPCRequest(.focus(project: project, worktree: worktree))
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

    func run() throws {
        try runIPCRequest(.send(project: project, worktree: worktree, window: window, keys: keys))
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

    func run() throws {
        try runIPCRequest(.newWindow(project: project, worktree: worktree, name: name))
    }
}

// MARK: - mori open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Open a project from a path")
    )

    @Argument(help: ArgumentHelp(.localized("Path to project directory")))
    var path: String

    func run() throws {
        try runIPCRequest(.open(path: path))
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

    func run() throws {
        try runIPCRequest(.setWorkflowStatus(project: project, worktree: worktree, status: status))
    }
}
