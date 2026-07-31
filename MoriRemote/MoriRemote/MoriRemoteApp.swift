import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var root = RemoteRootModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ghostty-terminal-probe") {
                GhosttyTerminalProbe()
            } else {
                RemoteRootView(root: root)
            }
            #else
            RemoteRootView(root: root)
            #endif
        }
    }
}
