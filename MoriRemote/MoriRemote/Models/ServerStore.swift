import Foundation
import Observation

@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []

    private static let fileName = "servers.json"

    init() {
        servers = Self.load()
    }

    func add(_ server: Server) {
        servers.append(server)
        save()
    }

    func update(_ server: Server) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        save()
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        save()
    }

    func delete(at offsets: IndexSet) {
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
            print("[ServerStore] save failed: \(error)")
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
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }
}
