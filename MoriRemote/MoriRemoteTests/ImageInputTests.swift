import Foundation
import Testing
@testable import MoriRemote

@Suite("Image input")
struct ImageInputTests {
    @Test("remote image paths are isolated, sanitized, and shell-visible")
    func pathBuilder() throws {
        let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let transferID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let paths = try SSHImageUploadPathBuilder().paths(
            workspaceID: workspaceID,
            transferID: transferID,
            filename: "../screen shot.png"
        )

        #expect(paths.directory == ".cache/mori/attachments/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222")
        #expect(paths.temporary.hasSuffix("/.screen shot.png.part"))
        #expect(paths.final.hasSuffix("/screen shot.png"))
        #expect(paths.terminal.hasPrefix("~/.cache/mori/attachments/"))
        #expect(!paths.final.contains("../"))
    }

    @Test("upload creates every directory and atomically renames the completed image")
    func transferOrdering() async throws {
        let session = RecordingUploadSession()
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("image".utf8).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }
        let paths = SSHImageUploadPaths(
            directory: ".cache/mori/attachments/workspace/transfer",
            temporary: ".cache/mori/attachments/workspace/transfer/.image.png.part",
            final: ".cache/mori/attachments/workspace/transfer/image.png",
            terminal: "~/.cache/mori/attachments/workspace/transfer/image.png"
        )
        let progress = ProgressRecorder()

        try await SSHImageUploadTransfer.run(
            session: session,
            localURL: localURL,
            paths: paths,
            totalBytes: 5,
            progress: { uploaded, total in await progress.append(uploaded, total) }
        )

        #expect(await session.events == [
            "mkdir:.cache",
            "mkdir:.cache/mori",
            "mkdir:.cache/mori/attachments",
            "mkdir:.cache/mori/attachments/workspace",
            "mkdir:.cache/mori/attachments/workspace/transfer",
            "remove:\(paths.temporary)",
            "upload:\(paths.temporary)",
            "rename:\(paths.temporary)->\(paths.final)",
        ])
        #expect(await progress.values.map(\.0) == [5])
        #expect(await progress.values.map(\.1) == [5])
    }
}

private actor ProgressRecorder {
    private(set) var values: [(Int64, Int64)] = []
    func append(_ uploaded: Int64, _ total: Int64) { values.append((uploaded, total)) }
}

private actor RecordingUploadSession: SSHFileUploadSession {
    private(set) var events: [String] = []

    func ensureDirectoryExists(atPath path: String) async throws {
        events.append("mkdir:\(path)")
    }

    func uploadFile(
        from localURL: URL,
        to remotePath: String,
        progress: @escaping SSHFileUploadProgressHandler
    ) async throws {
        events.append("upload:\(remotePath)")
        await progress(Int64((try Data(contentsOf: localURL)).count))
    }

    func renameFile(from temporaryPath: String, to finalPath: String) async throws {
        events.append("rename:\(temporaryPath)->\(finalPath)")
    }

    func removeFileIfExists(atPath path: String) async throws {
        events.append("remove:\(path)")
    }

    func close() async throws {
        events.append("close")
    }
}
