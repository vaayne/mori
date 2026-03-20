import Foundation
import MoriCore

public struct UIStateRepository: Sendable {
    private let store: JSONStore

    public init(store: JSONStore) {
        self.store = store
    }

    // MARK: - Read

    public func fetch() throws -> UIState {
        store.data.uiState
    }

    // MARK: - Write

    public func save(_ state: UIState) throws {
        store.mutate { data in
            data.uiState = state
        }
    }
}
