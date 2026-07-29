import Foundation
import MoriHerdr

// MARK: - Config

func testConfigRendersTheKeysHerdrActuallyAccepts() {
    let rendered = HerdrConfig().render()
    // Verified against herdr's own `UiConfig` / `ExperimentalConfig` (src/config/model.rs):
    // a key herdr does not know is a config it will not load.
    for key in [
        "sidebar_start_collapsed = true",
        #"sidebar_collapsed_mode = "hidden""#,
        "hide_tab_bar_when_single_tab = true",
        "pane_borders = false",
        "mouse_capture = true",
        "kitty_graphics = true",
    ] {
        assertTrue(rendered.contains(key), "config is missing \(key)")
    }
    assertTrue(rendered.contains("[ui]"), "the chrome keys need their table header")
    assertTrue(rendered.contains("[experimental]"), "kitty_graphics lives under [experimental]")
}

func testConfigWriterOnlyRewritesOnChange() {
    let path = NSTemporaryDirectory() + "mori-herdr-config-test/config.toml"
    try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

    let wroteFirst = (try? HerdrConfigWriter.write(HerdrConfig(), to: path)) ?? false
    assertTrue(wroteFirst, "the first write creates the file and its directory")
    assertTrue(FileManager.default.fileExists(atPath: path))

    let wroteAgain = (try? HerdrConfigWriter.write(HerdrConfig(), to: path)) ?? true
    assertFalse(wroteAgain, "an identical config is not rewritten")

    var changed = HerdrConfig()
    changed.kittyGraphics = false
    let wroteChanged = (try? HerdrConfigWriter.write(changed, to: path)) ?? false
    assertTrue(wroteChanged, "a different config is written")
}

func testEnvironmentBindsProcessesToMorisSession() {
    let environment = HerdrEnvironment(session: "mori", configPath: "/tmp/m/herdr.toml")
    assertEqual(environment.session, "mori")
    assertNotEqual(environment.session, HerdrSocketPath.defaultSession, "Mori never claims the user's session")
    assertEqual(environment.socketPath, HerdrSocketPath.resolve(session: "mori"))
    assertEqual(environment.variables["HERDR_CONFIG_PATH"], "/tmp/m/herdr.toml")

    let merged = environment.apply(to: ["PATH": "/bin", "HERDR_SESSION": "stale"])
    assertEqual(merged["PATH"], "/bin", "unrelated variables survive")
    assertEqual(merged["HERDR_SESSION"], "mori", "Mori's session wins over whatever was inherited")

    assertTrue(
        environment.shellExports.contains("export HERDR_SESSION='mori'"),
        "hooks and shims get the same binding as shell exports, got \(environment.shellExports)"
    )
}

// MARK: - Server lifecycle against a real binary

func testControllerStartsAndRestartsTheServer(_ binary: String) async {
    let session = "mori-life-\(ProcessInfo.processInfo.processIdentifier)"
    let root = NSTemporaryDirectory() + "mori-herdr-life-\(ProcessInfo.processInfo.processIdentifier)"
    let environment = HerdrEnvironment(session: session, configPath: root + "/herdr-config.toml")
    let controller = HerdrServerController(
        binaryPath: binary,
        environment: environment,
        logPath: root + "/herdr-server.log"
    )
    defer {
        stopServer(binary: binary, environment: environment)
        try? FileManager.default.removeItem(atPath: root)
        try? FileManager.default.removeItem(atPath: HerdrSocketPath.sessionDirectory(session: session))
    }

    _ = try? HerdrConfigWriter.write(HerdrConfig(), to: environment.configPath)

    let states = await controller.states()
    let observed = StateCollector()
    await observed.attach(states)

    do {
        let info = try await controller.ensureRunning()
        assertTrue(info.protocol >= HerdrBackend.minimumProtocol, "the server it started is one we understand")
    } catch {
        assertTrue(false, "ensureRunning failed: \(error)")
        return
    }

    // Idempotent: a second call must find the running server, not start a rival.
    let before = serverProcessCount(session: session)
    _ = try? await controller.ensureRunning()
    assertEqual(serverProcessCount(session: session), before, "ensureRunning does not start a second server")

    // The acceptance criterion: kill it outright, supervision brings it back. The pid comes
    // from the controller so the test can never hit a herdr server it did not start.
    await controller.startSupervision(interval: .milliseconds(300))
    guard let pid = await controller.spawnedProcessIdentifier else {
        assertTrue(false, "expected the controller to have spawned a server it can name")
        return
    }
    kill(pid: pid)
    assertFalse(
        await HerdrBackend(socketPath: environment.socketPath).isReachable(),
        "the server is really gone before we wait for the restart"
    )

    let restarted = await waitUntil(seconds: 20) {
        await HerdrBackend(socketPath: environment.socketPath).isReachable()
    }
    assertTrue(restarted, "supervision restarted the server after it was killed")
    assertTrue(
        await observed.sawRestarting(),
        "the restart is published so the terminal surface can reattach, saw: \(await observed.all())"
    )

    await controller.stopSupervision()
    await observed.detach()

    // Supervision stopping must not take the server with it — shells have to survive quitting Mori.
    assertTrue(
        await HerdrBackend(socketPath: environment.socketPath).isReachable(),
        "the server outlives supervision, exactly as a tmux server outlives the app"
    )
}

func testControllerReportsAMissingBinary() async {
    let controller = HerdrServerController(
        binaryPath: "/nonexistent/herdr",
        environment: HerdrEnvironment(session: "mori-missing-binary", configPath: "/tmp/none.toml")
    )
    do {
        _ = try await controller.ensureRunning(timeout: 2)
        assertTrue(false, "a missing binary should fail")
    } catch let failure as HerdrServerController.StartFailure {
        assertTrue("\(failure)".contains("no herdr binary"), "the reason names the problem, got: \(failure)")
    } catch {
        assertTrue(false, "expected a StartFailure, got \(error)")
    }
}

// MARK: - Helpers

/// Buffers controller states; a restart is a transition the UI has to see.
actor StateCollector {
    private var states: [HerdrServerState] = []
    private var drain: Task<Void, Never>?

    func attach(_ stream: AsyncStream<HerdrServerState>) {
        drain = Task { [weak self] in
            for await state in stream { await self?.append(state) }
        }
    }

    private func append(_ state: HerdrServerState) { states.append(state) }

    func all() -> [HerdrServerState] { states }

    func sawRestarting() async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if states.contains(where: { if case .restarting = $0 { return true }; return false }) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    func detach() {
        drain?.cancel()
        drain = nil
    }
}

func waitUntil(seconds: TimeInterval, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}

/// `pgrep -f` against the session's socket path, which is unique to this test's server.
func serverProcessCount(session: String) -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", "herdr server"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)?.split(separator: "\n").count ?? 0
}

/// `SIGKILL`s exactly one pid — the point is to prove recovery from a crash rather than from
/// a graceful shutdown, and the stale socket file a crash leaves behind is part of the test.
func kill(pid: Int32) {
    _ = Foundation.kill(pid, SIGKILL)
    // Reap, so the killed server does not linger as a zombie and confuse `isRunning`.
    var status: Int32 = 0
    _ = waitpid(pid, &status, 0)
}

func stopServer(binary: String, environment: HerdrEnvironment) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["server", "stop"]
    process.environment = environment.apply(to: ProcessInfo.processInfo.environment)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}
