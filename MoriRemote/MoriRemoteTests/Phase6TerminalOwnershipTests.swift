import Foundation
import Testing
@testable import MoriRemote

@Suite("Terminal facade ownership") struct Phase6TerminalOwnershipTests {
    @Test("adaptive workspace chrome retains its terminal session identity")
    func workspaceSessionIdentity() {
        let session = UUID()
        #expect(WorkspaceTerminalPresentation.identity(for: session) == session)
        #expect(WorkspaceTerminalPresentation.identity(for: session) == session)
        #expect(WorkspaceTerminalPresentation.identity(for: UUID()) != session)
    }

    @Test("app target has no direct native terminal owner or Ghostty link")
    func oneOwnerInvariant() throws {
        let remoteRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSources = remoteRoot.appendingPathComponent("MoriRemote")
        let forbiddenPaths = [
            "Ghostty/GhosttyKitRuntime.swift",
            "Ghostty/GhosttyPaneSurface.swift",
            "Ghostty/GhosttyTmuxRuntime.swift",
            "Ghostty/GhosttyTerminalProbe.swift",
            "GhosttyKitABIProbe.swift",
            "Tmux/TmuxControl.swift",
            "Tmux/TmuxSessionController.swift",
            "Tmux/DeterministicTmuxControlTransport.swift",
        ]
        for path in forbiddenPaths {
            #expect(!FileManager.default.fileExists(atPath: appSources.appendingPathComponent(path).path))
        }

        let appSwiftFiles = try FileManager.default.contentsOfDirectory(
            at: appSources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let directImports = try appSwiftFiles.flatMap { root in
            try recursiveSwiftFiles(at: root)
        }.filter { url in
            try String(contentsOf: url).contains("import GhosttyKit")
        }
        #expect(directImports.isEmpty)

        let project = try String(contentsOf: remoteRoot.appendingPathComponent("project.yml"))
        let appTarget = try #require(project.components(separatedBy: "  MoriRemoteTerminal:").first)
        #expect(!appTarget.contains("GhosttyKit.xcframework"))
        #expect(!appTarget.contains("ghostty_tmux_client_config_new"))
    }

    private func recursiveSwiftFiles(at url: URL) throws -> [URL] {
        if url.pathExtension == "swift" { return [url] }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .flatMap { try recursiveSwiftFiles(at: $0) }
    }
}
