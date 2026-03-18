import Foundation

/// Built-in session templates for common development workflows.
public enum TemplateRegistry {

    /// Basic template: shell, run, logs.
    public static let basic = SessionTemplate(
        name: "basic",
        windows: [
            WindowTemplate(name: "shell"),
            WindowTemplate(name: "run"),
            WindowTemplate(name: "logs"),
        ]
    )

    /// Go template: editor, server, tests, logs.
    public static let go = SessionTemplate(
        name: "go",
        windows: [
            WindowTemplate(name: "editor"),
            WindowTemplate(name: "server", command: "go run ."),
            WindowTemplate(name: "tests", command: "go test ./..."),
            WindowTemplate(name: "logs"),
        ]
    )

    /// Agent template: editor, agent, server, logs.
    public static let agent = SessionTemplate(
        name: "agent",
        windows: [
            WindowTemplate(name: "editor"),
            WindowTemplate(name: "agent"),
            WindowTemplate(name: "server"),
            WindowTemplate(name: "logs"),
        ]
    )

    /// All built-in templates.
    public static let all: [SessionTemplate] = [basic, go, agent]

    /// Look up a template by name. Returns `basic` if not found.
    public static func template(named name: String) -> SessionTemplate {
        all.first { $0.name == name } ?? basic
    }
}
