import ArgumentParser
import Foundation
import MoriIPC

@main
struct MoriCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mori",
        abstract: String(localized: "Mori workspace CLI — communicate with the running Mori app.", bundle: .module),
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
        abstract: String(localized: "Project commands", bundle: .module),
        subcommands: [ProjectList.self]
    )
}

struct ProjectList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: String(localized: "List all projects", bundle: .module)
    )

    func run() throws {
        try runIPCRequest(.projectList)
    }
}

// MARK: - mori worktree

struct WorktreeCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: String(localized: "Worktree commands", bundle: .module),
        subcommands: [WorktreeCreate.self]
    )
}

struct WorktreeCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: String(localized: "Create a new worktree", bundle: .module)
    )

    @Argument(help: ArgumentHelp(String(localized: "Project name", bundle: .module)))
    var project: String

    @Argument(help: ArgumentHelp(String(localized: "Branch name", bundle: .module)))
    var branch: String

    func run() throws {
        try runIPCRequest(.worktreeCreate(project: project, branch: branch))
    }
}

// MARK: - mori focus

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: String(localized: "Focus a project and worktree", bundle: .module)
    )

    @Argument(help: ArgumentHelp(String(localized: "Project name", bundle: .module)))
    var project: String

    @Argument(help: ArgumentHelp(String(localized: "Worktree name", bundle: .module)))
    var worktree: String

    func run() throws {
        try runIPCRequest(.focus(project: project, worktree: worktree))
    }
}

// MARK: - mori send

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: String(localized: "Send keys to a tmux window", bundle: .module)
    )

    @Argument(help: ArgumentHelp(String(localized: "Project name", bundle: .module)))
    var project: String

    @Argument(help: ArgumentHelp(String(localized: "Worktree name", bundle: .module)))
    var worktree: String

    @Argument(help: ArgumentHelp(String(localized: "Window name", bundle: .module)))
    var window: String

    @Argument(help: ArgumentHelp(String(localized: "Keys to send", bundle: .module)))
    var keys: String

    func run() throws {
        try runIPCRequest(.send(project: project, worktree: worktree, window: window, keys: keys))
    }
}

// MARK: - mori new-window

struct NewWindow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-window",
        abstract: String(localized: "Create a new window in a worktree", bundle: .module)
    )

    @Argument(help: ArgumentHelp(String(localized: "Project name", bundle: .module)))
    var project: String

    @Argument(help: ArgumentHelp(String(localized: "Worktree name", bundle: .module)))
    var worktree: String

    @Option(name: .long, help: ArgumentHelp(String(localized: "Window name", bundle: .module)))
    var name: String?

    func run() throws {
        try runIPCRequest(.newWindow(project: project, worktree: worktree, name: name))
    }
}

// MARK: - mori open

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: String(localized: "Open a project from a path", bundle: .module)
    )

    @Argument(help: ArgumentHelp(String(localized: "Path to project directory", bundle: .module)))
    var path: String

    func run() throws {
        try runIPCRequest(.open(path: path))
    }
}
