import Foundation

enum GhosttyRuntimeTrace {
    private static let diagnosticsEnabled =
        ProcessInfo.processInfo.environment["REMUX_TRACE_GHOSTTY_IO"] == "1"
        || ProcessInfo.processInfo.environment["REMUX_TRACE_GHOSTTY_DIAGNOSTICS"] == "1"
    static let perfEnabled = ProcessInfo.processInfo.environment["REMUX_TRACE_PERF"] == "1"
    private static let tmuxViewportEnabled =
        ProcessInfo.processInfo.environment["REMUX_TRACE_TMUX_VIEWPORT"] == "1"

    static func nowNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func elapsedMilliseconds(
        from start: UInt64,
        to end: UInt64 = nowNanos()
    ) -> String {
        String(format: "%.3f", Double(end &- start) / 1_000_000)
    }

    static func diagnostics(_ message: @autoclosure () -> String) {
        guard diagnosticsEnabled else { return }
        NSLog("MoriRemote diag %@", message())
    }

    static func perf(_ message: @autoclosure () -> String) {
        guard perfEnabled else { return }
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        NSLog("MoriRemote perf t=%llu thread=%@ %@", nowNanos(), thread, message())
    }

    static func tmuxViewport(_ message: @autoclosure () -> String) {
        guard tmuxViewportEnabled else { return }
        NSLog("MoriRemote tmuxViewport t=%llu %@", nowNanos(), message())
    }
}
