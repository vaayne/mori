import Foundation
import MoriTmux

/// Applies Mori's onboarding-focused tmux defaults to Mori-managed sessions only.
enum TmuxPresetApplicator {
    private static let presetResourceName = "mori-tmux-preset"
    private static let compatibilityCleanupOptions: Set<String> = [
        "mouse",
        "status",
    ]
    private static let presetAssignments = loadPresetAssignments()

    static func apply(enabled: Bool, tmuxBackend: TmuxBackend) async {
        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                if enabled {
                    await applyPresetAssignments(session: session, tmuxBackend: tmuxBackend)
                } else {
                    await clearPresetAssignments(session: session, tmuxBackend: tmuxBackend)
                }
            }
        } catch {
            print("[TmuxPresetApplicator] Failed to list sessions for Mori preset application: \(error)")
        }
    }

    private static func loadPresetAssignments() -> [TmuxPresetAssignment] {
        guard let url = MoriAppResourceBundle.resourceBundle?.url(
            forResource: presetResourceName,
            withExtension: "conf"
        ) else {
            print("[TmuxPresetApplicator] Missing bundled preset resource \(presetResourceName).conf; skipping Mori tmux preset application.")
            return []
        }

        do {
            let presetSource = try String(contentsOf: url, encoding: .utf8)
            let assignments = try TmuxPresetParser.parse(presetSource)
            let sessionAssignments = assignments.filter { $0.scope == .session }
            if sessionAssignments.count != assignments.count {
                print("[TmuxPresetApplicator] Bundled preset resource \(presetResourceName).conf contains window-scoped options, which are not supported yet; ignoring those entries.")
            }
            return sessionAssignments
        } catch {
            print("[TmuxPresetApplicator] Failed to parse bundled preset resource \(presetResourceName).conf: \(error)")
            return []
        }
    }

    private static func applyPresetAssignments(session: TmuxSession, tmuxBackend: TmuxBackend) async {
        for assignment in presetAssignments {
            try? await tmuxBackend.setOption(
                sessionId: session.id,
                option: assignment.option,
                value: assignment.value
            )
        }
    }

    private static func clearPresetAssignments(session: TmuxSession, tmuxBackend: TmuxBackend) async {
        let optionsToClear = compatibilityCleanupOptions.union(presetAssignments.map(\.option))
        for option in optionsToClear {
            try? await tmuxBackend.unsetOption(sessionId: session.id, option: option)
        }
    }
}
