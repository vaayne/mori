import Foundation
import Observation
import os.log

private let log = Logger(subsystem: "com.vaayne.mori.remote", category: "ServerStore")

@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []

    private static let fileName = "servers.json"

    init() {
        servers = Self.load()
    }

    func add(_ server: Server) {
        server.savePasswordToKeychain()
        servers.append(server)
        save()
    }

    func update(_ server: Server) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        server.savePasswordToKeychain()
        servers[index] = server
        save()
    }

    func delete(_ server: Server) {
        server.deletePasswordFromKeychain()
        servers.removeAll { $0.id == server.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            servers[index].deletePasswordFromKeychain()
        }
        servers.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        servers.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            log.error("Save failed: \(error.localizedDescription)")
        }
    }

    private static func load() -> [Server] {
        guard let data = try? Data(contentsOf: fileURL),
              let servers = try? JSONDecoder().decode([Server].self, from: data)
        else {
            return []
        }
        return servers
    }

    private static var fileURL: URL {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Fallback to temp directory — should never happen on iOS
            return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
        return dir.appendingPathComponent(fileName)
    }
}
