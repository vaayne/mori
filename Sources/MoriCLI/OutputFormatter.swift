import Foundation

// MARK: - Table Formatter

/// Formats arrays of rows into aligned columns for terminal output.
enum TableFormatter {

    static func format(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }

        var lines: [String] = []

        // Header
        let headerLine = headers.enumerated().map { i, h in
            h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        lines.append(headerLine)

        // Separator
        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ")
        lines.append(separator)

        // Data rows
        for row in rows {
            let cells = headers.indices.map { i in
                let cell = i < row.count ? row[i] : ""
                return cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }
            lines.append(cells.joined(separator: "  "))
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Decodable models for CLI-side JSON parsing

struct CLIProjectEntry: Decodable {
    let name: String
    let path: String
}

struct CLIWorktreeEntry: Decodable {
    let name: String
    let branch: String
    let path: String
}

struct CLIPaneInfo: Decodable {
    let endpoint: String
    let tmuxPaneId: String
    let projectName: String
    let worktreeName: String
    let windowName: String
    let paneTitle: String?
    let agentState: String
    let detectedAgent: String?
}

// MARK: - Formatting helpers

enum OutputFormat {

    static func formatProjectList(_ data: Data) -> String {
        guard let projects = try? JSONDecoder().decode([CLIProjectEntry].self, from: data) else {
            return prettyJSON(data)
        }
        if projects.isEmpty { return .localized("No projects found.") }
        let rows = projects.map { [$0.name, $0.path] }
        return TableFormatter.format(
            headers: [.localized("Name"), .localized("Path")],
            rows: rows
        )
    }

    static func formatWorktreeCreate(_ data: Data) -> String {
        guard let wt = try? JSONDecoder().decode(CLIWorktreeEntry.self, from: data) else {
            return prettyJSON(data)
        }
        return "✓ " + String(format: .localized("Created worktree '%@' on branch '%@' at %@"), wt.name, wt.branch, wt.path)
    }

    static func formatProjectOpen(_ data: Data) -> String {
        guard let project = try? JSONDecoder().decode(CLIProjectEntry.self, from: data) else {
            return prettyJSON(data)
        }
        return "✓ " + String(format: .localized("Opened project '%@' (%@)"), project.name, project.path)
    }

    static func formatPaneList(_ data: Data) -> String {
        guard let panes = try? JSONDecoder().decode([CLIPaneInfo].self, from: data) else {
            return prettyJSON(data)
        }
        if panes.isEmpty { return .localized("No panes found.") }
        let rows = panes.map { pane in
            [
                pane.projectName,
                pane.worktreeName,
                pane.windowName,
                pane.tmuxPaneId,
                pane.detectedAgent ?? "–",
                formatAgentState(pane.agentState),
            ]
        }
        return TableFormatter.format(
            headers: [
                .localized("Project"),
                .localized("Worktree"),
                .localized("Window"),
                .localized("Pane"),
                .localized("Agent"),
                .localized("State"),
            ],
            rows: rows
        )
    }

    static func formatSuccess(_ label: String) -> String {
        "✓ \(label)"
    }

    // MARK: - Private

    private static func formatAgentState(_ raw: String) -> String {
        switch raw {
        case "none": return "–"
        case "running": return "⚡ running"
        case "waitingForInput": return "⏳ waiting"
        case "error": return "✗ error"
        case "completed": return "✓ done"
        default: return raw
        }
    }

    static func prettyJSON(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
