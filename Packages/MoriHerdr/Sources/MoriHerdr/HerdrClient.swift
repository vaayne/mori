import Foundation

/// The herdr socket API: newline-delimited JSON over `AF_UNIX`.
///
/// **One request per connection.** The server answers and closes, so `call` opens a fresh
/// socket every time rather than pooling — pooling would only produce broken pipes. The one
/// exception is `events.subscribe`, which holds its connection open for the life of the
/// stream; that is `openSubscription`'s job, and `HerdrEventStream` owns the policy around it.
public struct HerdrClient: Sendable {
    public let socketPath: String
    public let timeout: TimeInterval

    public init(socketPath: String, timeout: TimeInterval = 5) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    // MARK: - Requests

    @discardableResult
    public func call(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> JSONValue {
        let connection = HerdrConnection(path: socketPath)
        defer { connection.close() }

        connection.armDeadline(timeout, error: HerdrError.timeout(method: method))
        try await connection.open(timeout: timeout)
        let id = "mori-\(UUID().uuidString.prefix(8))"
        try await connection.send(try encodeRequest(id: id, method: method, params: params))
        return try await awaitResult(on: connection, id: id, method: method)
    }

    public func call<Result: Decodable & Sendable>(
        _ method: String,
        _ params: [String: JSONValue] = [:],
        as type: Result.Type
    ) async throws -> Result {
        let result = try await call(method, params)
        return try decode(result, method: method, as: type)
    }

    // MARK: - Subscriptions

    /// Starts an event subscription and hands back the still-open connection.
    ///
    /// Returns only after the server acknowledges, so a rejected subscription surfaces
    /// here rather than as a stream that silently never yields. herdr validates the list
    /// as a whole: one bad entry fails the request with an empty `id` and closes the
    /// socket, which is why the ack loop accepts an error under any id.
    func openSubscription(_ subscriptions: [HerdrSubscription]) async throws -> HerdrConnection {
        let method = "events.subscribe"
        let connection = HerdrConnection(path: socketPath)
        connection.armDeadline(timeout, error: HerdrError.timeout(method: method))
        do {
            try await connection.open(timeout: timeout)
            let id = "mori-sub-\(UUID().uuidString.prefix(8))"
            let params: [String: JSONValue] = ["subscriptions": .array(subscriptions.map(\.json))]
            try await connection.send(try encodeRequest(id: id, method: method, params: params))
            _ = try await awaitResult(on: connection, id: id, method: method)
        } catch {
            connection.close()
            throw error
        }
        connection.clearDeadline() // the stream is open-ended from here
        return connection
    }

    // MARK: - Framing

    private func encodeRequest(id: String, method: String, params: [String: JSONValue]) throws -> Data {
        let request = JSONValue.object([
            "id": .string(id),
            "method": .string(method),
            "params": .object(params),
        ])
        return try JSONEncoder().encode(request)
    }

    /// Reads until the response for `id` arrives.
    ///
    /// Skips unrelated lines — a subscription connection can interleave pushed events with
    /// a reply — but takes any error envelope, because herdr reports malformed requests
    /// under an empty id it could not parse.
    private func awaitResult(on connection: HerdrConnection, id: String, method: String) async throws -> JSONValue {
        while let line = try await connection.nextLine() {
            let message: JSONValue
            do {
                message = try JSONDecoder().decode(JSONValue.self, from: line)
            } catch {
                continue // not JSON we understand; the response may still be coming
            }
            if let error = message["error"], case .object = error {
                throw HerdrError.server(
                    method: method,
                    error: try decode(error, method: method, as: HerdrServerError.self)
                )
            }
            guard message["id"]?.stringValue == id else { continue }
            return message["result"] ?? .object([:])
        }
        throw HerdrError.connectionClosed(method: method)
    }

    private func decode<Result: Decodable>(_ value: JSONValue, method: String, as type: Result.Type) throws -> Result {
        do {
            return try JSONDecoder().decode(type, from: try JSONEncoder().encode(value))
        } catch {
            throw HerdrError.decodingFailed(method: method, underlying: "\(error)")
        }
    }
}
