import Foundation

struct Server: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var defaultSession: String

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        password: String = "",
        defaultSession: String = "main"
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.defaultSession = defaultSession
    }

    /// Display label — falls back to user@host if name is empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let userHost = "\(username)@\(host)"
        return port != 22 ? "\(userHost):\(port)" : userHost
    }

    var subtitle: String {
        let addr = port != 22 ? "\(host):\(port)" : host
        return "\(username)@\(addr)"
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        port > 0 && port <= 65535
    }
}
