import Foundation

/// Encodes a control message to JSON data for sending as a text WebSocket frame.
public func encodeMessage(_ message: ControlMessage) throws -> Data {
    try JSONEncoder().encode(message)
}

/// Decodes a control message from JSON data received as a text WebSocket frame.
public func decodeMessage(_ data: Data) throws -> ControlMessage {
    try JSONDecoder().decode(ControlMessage.self, from: data)
}
