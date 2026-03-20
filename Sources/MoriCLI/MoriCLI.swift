import ArgumentParser
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
        let errorMessage = String.localized("Error: \(message)")
        FileHandle.standardError.write(Data(errorMessage.utf8))
        throw ExitCode.failure
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
