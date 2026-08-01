import SwiftUI
import UIKit

@main
struct MoriRemoteApp: App {
    @State private var root = RemoteRootModel()

    var body: some Scene {
        WindowGroup {
            Group {
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                root.handleMemoryWarning()
            }
        }
    }
}
