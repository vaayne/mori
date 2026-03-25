import SwiftUI
import GhosttyKit

@main
struct MoriRemoteApp: App {
    @State private var ghosttyReady = false
    @State private var errorMessage: String?

    init() {
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result == GHOSTTY_SUCCESS {
            _ghosttyReady = State(initialValue: true)
        } else {
            _errorMessage = State(initialValue: "ghostty_init failed with code \(result)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ghosttyReady {
                TerminalView()
            } else {
                Text(errorMessage ?? "Unknown error")
                    .foregroundStyle(.red)
            }
        }
    }
}
