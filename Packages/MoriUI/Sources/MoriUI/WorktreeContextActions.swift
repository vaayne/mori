import SwiftUI
import MoriCore

/// The single source of truth for a worktree's menu items, shared by the row's
/// hover "•••" menu and its right-click context menu so the two never drift.
/// Renders as menu content (a sequence of Buttons/Dividers) — drop it inside a
/// `Menu { }` or `.contextMenu { }`.
struct WorktreeContextActions: View {
    let worktree: Worktree
    let pullRequest: PullRequestInfo?
    var onRemove: (() -> Void)?

    var body: some View {
        let editors = EditorLauncher.installed
        if !editors.isEmpty {
            ForEach(editors) { editor in
                Button {
                    editor.open(path: worktree.path)
                } label: {
                    Label("Open in \(editor.name)", systemImage: editor.icon)
                }
            }
            Divider()
        }

        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        if let pullRequest, let github = URL(string: pullRequest.url) {
            Divider()
            Button {
                NSWorkspace.shared.open(github)
            } label: {
                Label("Open PR on GitHub", systemImage: "arrow.up.forward.app")
            }
            if let diffshub = diffsHubURL(from: github) {
                Button {
                    NSWorkspace.shared.open(diffshub)
                } label: {
                    Label("Open PR on DiffsHub", systemImage: "arrow.up.forward.square")
                }
            }
        }

        if !worktree.isMainWorktree, let onRemove {
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove Worktree…", systemImage: "trash")
            }
        }
    }

    /// DiffsHub mirrors a github.com PR at the same path on its own host. Returns
    /// nil for non-github.com URLs (e.g. GHE) so the option simply doesn't appear.
    private func diffsHubURL(from github: URL) -> URL? {
        guard var components = URLComponents(url: github, resolvingAgainstBaseURL: false),
              components.host == "github.com" else { return nil }
        components.host = "diffshub.com"
        return components.url
    }
}
