import ArgumentParser
import Foundation
import MoriIPC

@main
struct WS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ws",
        abstract: "Mori workspace CLI — communicate with the running Mori app.",
        subcommands: [
            Project.self,
            WorktreeCmd.self,
            Focus.self,
            Send.self,
            NewWindow.self,
            Open.self,
        ]
    )
}

// MARK: - Shared Helpers

/// Send an IPC request and print the result as JSON.
func runIPCRequest(_ command: IPCCommand) throws {
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
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        throw ExitCode.failure
    }
}

// MARK: - ws project

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Project commands",
        subcommands: [ProjectList.self]
    )
}

struct ProjectList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all projects"
    )

    func run() throws {
        try runIPCRequest(.projectList)
    }
}

// MARK: - ws worktree

struct WorktreeCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Worktree commands",
        subcommands: [WorktreeCreate.self]
    )
}

struct WorktreeCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new worktree"
    )

    @Argument(help: "Project name")
    var project: String

    @Argument(help: "Branch name")
    var branch: String

    func run() throws {
        try runIPCRequest(.worktreeCreate(project: project, branch: branch))
    }
}

// MARK: - ws focus

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Focus a project and worktree"
    )

    @Argument(help: "Project name")
    var project: String

    @Argument(help: "Worktree name")
    var worktree: String

    func run() throws {
        try runIPCRequest(.focus(project: project, worktree: worktree))
    }
}

// MARK: - ws send

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send keys to a tmux window"
    )

    @Argument(help: "Project name")
    var project: String

    @Argument(help: "Worktree name")
    var worktree: String

    @Argument(help: "Window name")
    var window: String

    @Argument(help: "Keys to send")
    var keys: String

    func run() throws {
        try runIPCRequest(.send(project: project, worktree: worktree, window: window, keys: keys))
    }
}

// MARK: - ws new-window

struct NewWindow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-window",
        abstract: "Create a new window in a worktree"
    )

    @Argument(help: "Project name")
    var project: String

    @Argument(help: "Worktree name")
    var worktree: String

    @Option(name: .long, help: "Window name")
    var name: String?

    func run() throws {
        try runIPCRequest(.newWindow(project: project, worktree: worktree, name: name))
    }
}

// MARK: - ws open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a project from a path"
    )

    @Argument(help: "Path to project directory")
    var path: String

    func run() throws {
        try runIPCRequest(.open(path: path))
    }
}
