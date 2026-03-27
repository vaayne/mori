import MoriCore

extension Project {
    var resolvedLocation: WorkspaceLocation {
        location ?? .local
    }
}

extension Worktree {
    var resolvedLocation: WorkspaceLocation {
        location ?? .local
    }
}

enum WorkspaceEndpoint {
    static let separator = "|"

    static func namespacedWindowId(rawWindowId: String, location: WorkspaceLocation) -> String {
        "\(location.endpointKey)\(separator)\(rawWindowId)"
    }

    static func rawWindowId(from namespaced: String) -> String {
        guard let range = namespaced.range(of: separator) else {
            return namespaced
        }
        return String(namespaced[range.upperBound...])
    }
}

