import Darwin
import Foundation

/// Local-only helper for materializing a workspace as an APFS copy-on-write
/// clone (`clonefile` via `copyfile()`), with the git fixup needed to turn a
/// cloned repository into a usable branch checkout.
///
/// Not part of `GitControlling`: that protocol is also implemented for SSH,
/// and cloning is inherently a local-filesystem operation. `WorkspaceManager`
/// uses this type directly for local projects and falls back to `git worktree`
/// (or a plain copy) when cloning is not possible.
public enum CowCloner {

    /// On-disk shape of a workspace directory, derived from its `.git` entry.
    public enum OnDiskKind: Sendable, Equatable {
        /// `.git` is a directory → a full (cloned or standalone) repository.
        case fullRepo
        /// `.git` is a regular file → a linked `git worktree`.
        case linkedWorktree
        /// No `.git` entry → a plain directory.
        case plainDirectory
    }

    public enum CowCloneError: Error, LocalizedError {
        /// The destination already exists; refuse to overwrite.
        case destinationExists(String)
        /// `clonefile` failed — typically cross-volume or a non-APFS target.
        /// Callers treat this as "fall back to another strategy".
        case cloneUnsupported(errno: Int32, message: String)

        public var errorDescription: String? {
            switch self {
            case .destinationExists(let path):
                return "Destination already exists: \(path)"
            case .cloneUnsupported(let code, let message):
                return "Copy-on-write clone failed (errno \(code)): \(message)"
            }
        }
    }

    // MARK: - Classification

    /// Classify a workspace directory by inspecting its `.git` entry. Pure and
    /// safe to call before any destructive operation.
    public static func classify(path: String) -> OnDiskKind {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir) {
            return isDir.boolValue ? .fullRepo : .linkedWorktree
        }
        return .plainDirectory
    }

    // MARK: - Clone

    /// Clone `source` to `dest` using an APFS copy-on-write `clonefile`.
    ///
    /// Writes to a sibling temp path first, then renames into place, so a
    /// partially-written clone never appears at `dest`. Fails (throwing
    /// `.destinationExists`) if `dest` already exists, and `.cloneUnsupported`
    /// when the volume can't clone — the copy is never silently downgraded to a
    /// slow physical copy, so callers can choose their own fallback.
    ///
    /// Fast path: a single `clonefile(2)` on the root directory clones the whole
    /// tree in one syscall (~1.7s for a 4 GB repo incl. build artifacts,
    /// measured), sockets included. Only when that refuses does this fall back
    /// to the per-file `copyfile` walk, which can take tens of seconds on large
    /// trees — call off the main actor either way.
    public static func clone(from source: String, to dest: String) throws {
        guard !FileManager.default.fileExists(atPath: dest) else {
            throw CowCloneError.destinationExists(dest)
        }

        let shortID = String(UUID().uuidString.prefix(8))
        let tempPath = "\(dest).tmp-\(shortID)"
        // Defensive: a stale temp from a crashed run would make the clone fail.
        try? FileManager.default.removeItem(atPath: tempPath)

        do {
            if clonefile(source, tempPath, 0) != 0 {
                try copyfileClone(from: source, to: tempPath)
            }
            try FileManager.default.moveItem(atPath: tempPath, toPath: dest)
        } catch {
            try? FileManager.default.removeItem(atPath: tempPath)
            throw error
        }
    }

    /// Raw copy-on-write clone with a status callback that skips sockets/FIFOs
    /// (e.g. `.git/fsmonitor--daemon.ipc`) instead of aborting.
    ///
    /// A pre-flight check rejects cross-volume and non-cloning (non-APFS)
    /// targets, throwing `.cloneUnsupported` so the caller can fall back — this
    /// is what guarantees the clone never silently degrades into a slow physical
    /// copy. On a cloning-capable, same-volume target the soft `COPYFILE_CLONE`
    /// always takes the copy-on-write fast path.
    ///
    /// (`COPYFILE_CLONE_FORCE` cannot be used here: on macOS it fails with
    /// ENOTSUP/EINVAL for directory trees because interior directory nodes are
    /// created via `mkdir` rather than cloned. The volume pre-check preserves
    /// the same "no silent physical copy" guarantee.)
    private static func copyfileClone(from source: String, to dest: String) throws {
        let destParent = (dest as NSString).deletingLastPathComponent
        try verifyCloneable(source: source, destinationParent: destParent)

        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }

        // No captures → usable as a C function pointer.
        let callback: copyfile_callback_t = { what, _, _, src, _, _ in
            // Proactively skip sockets and FIFOs; clonefile can't reproduce them
            // and `cp`-style tools error out on them.
            if what == COPYFILE_RECURSE_FILE || what == COPYFILE_RECURSE_ERROR {
                if let src {
                    var st = stat()
                    if lstat(src, &st) == 0 {
                        let type = st.st_mode & S_IFMT
                        if type == S_IFSOCK || type == S_IFIFO {
                            return Int32(COPYFILE_SKIP)
                        }
                    }
                }
            }
            // Any real error (e.g. clone unsupported on this volume) aborts, so
            // the overall copyfile fails cleanly rather than degrading.
            if what == COPYFILE_RECURSE_ERROR {
                return Int32(COPYFILE_QUIT)
            }
            return Int32(COPYFILE_CONTINUE)
        }
        _ = copyfile_state_set(
            state,
            UInt32(COPYFILE_STATE_STATUS_CB),
            unsafeBitCast(callback, to: UnsafeRawPointer.self)
        )

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE)
        let result = source.withCString { src in
            dest.withCString { dst in
                copyfile(src, dst, state, flags)
            }
        }
        if result != 0 {
            let code = errno
            throw CowCloneError.cloneUnsupported(
                errno: code,
                message: String(cString: strerror(code))
            )
        }
    }

    /// Reject targets where an APFS clone is impossible: a volume that doesn't
    /// support file cloning, or a destination on a different volume than the
    /// source. Both cases would otherwise make `copyfile` silently fall back to
    /// a physical copy.
    private static func verifyCloneable(source: String, destinationParent: String) throws {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey, .volumeSupportsFileCloningKey]
        let sourceValues = try? URL(fileURLWithPath: source).resourceValues(forKeys: keys)
        let destValues = try? URL(fileURLWithPath: destinationParent).resourceValues(forKeys: keys)

        guard destValues?.volumeSupportsFileCloning == true else {
            throw CowCloneError.cloneUnsupported(
                errno: Int32(ENOTSUP),
                message: "destination volume does not support file cloning"
            )
        }
        guard let sourceVolume = sourceValues?.volumeIdentifier as? AnyHashable,
              let destVolume = destValues?.volumeIdentifier as? AnyHashable,
              sourceVolume == destVolume else {
            throw CowCloneError.cloneUnsupported(
                errno: Int32(EXDEV),
                message: "source and destination are on different volumes"
            )
        }
    }

    // MARK: - Git fixup

    /// Turn a freshly cloned full repository into a clean checkout of `branch`.
    ///
    /// - Removes the inherited `.git/worktrees` registrations (stale links to
    ///   the source repo's worktrees).
    /// - `git checkout -f -B <branch> [<base>]` for a new branch, or
    ///   `git checkout -f <branch>` for an existing one. `-f` intentionally
    ///   resets tracked dirty state inherited from the source; untracked files
    ///   (node_modules, .build, …) are preserved — that is the whole point.
    ///
    /// No-op unless `clonePath/.git` is a directory (i.e. a real clone).
    public static func gitFixup(
        clonePath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        runner: GitCommandRunner = GitCommandRunner()
    ) async throws {
        guard classify(path: clonePath) == .fullRepo else { return }

        let worktreesDir = (clonePath as NSString)
            .appendingPathComponent(".git")
        let stale = (worktreesDir as NSString).appendingPathComponent("worktrees")
        try? FileManager.default.removeItem(atPath: stale)

        if createBranch {
            var args = ["checkout", "-f", "-B", branch]
            if let baseBranch, !baseBranch.isEmpty {
                args.append(baseBranch)
            }
            _ = try await runner.run(in: clonePath, args)
        } else {
            _ = try await runner.run(in: clonePath, ["checkout", "-f", branch])
        }
    }
}
