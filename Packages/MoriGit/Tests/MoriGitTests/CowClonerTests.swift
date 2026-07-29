import Foundation
import MoriGit

// MARK: - Helpers

private func makeTempDir(_ label: String) -> String {
    let base = NSTemporaryDirectory()
    let path = (base as NSString).appendingPathComponent("moritest-\(label)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func write(_ contents: String, to path: String) {
    try? contents.write(toFile: path, atomically: true, encoding: .utf8)
}

private func read(_ path: String) -> String? {
    try? String(contentsOfFile: path, encoding: .utf8)
}

private func join(_ dir: String, _ component: String) -> String {
    (dir as NSString).appendingPathComponent(component)
}

// MARK: - clone: content + symlink

func testCowCloneCopiesTreeAndSymlink() {
    let root = makeTempDir("clone-src")
    defer { try? FileManager.default.removeItem(atPath: root) }

    let source = join(root, "source")
    try? FileManager.default.createDirectory(atPath: join(source, "sub"), withIntermediateDirectories: true)
    write("hello", to: join(source, "file1.txt"))
    write("world", to: join(source, "sub/file2.txt"))
    // Relative symlink to a sibling file.
    try? FileManager.default.createSymbolicLink(
        atPath: join(source, "link"),
        withDestinationPath: "file1.txt"
    )

    let dest = join(root, "dest")
    do {
        try CowCloner.clone(from: source, to: dest)
    } catch {
        assertTrue(false, "clone threw unexpectedly: \(error)")
        return
    }

    assertEqual(read(join(dest, "file1.txt")), "hello", "top-level file cloned")
    assertEqual(read(join(dest, "sub/file2.txt")), "world", "nested file cloned")

    // Symlink preserved as a symlink pointing at the same relative target.
    let linkPath = join(dest, "link")
    let attrs = try? FileManager.default.attributesOfItem(atPath: linkPath)
    assertEqual(attrs?[.type] as? FileAttributeType, FileAttributeType.typeSymbolicLink, "link is a symlink")
    let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
    assertEqual(target, "file1.txt", "symlink target preserved")
}

// MARK: - clone: destination exists

func testCowCloneFailsWhenDestExists() {
    let root = makeTempDir("clone-exists")
    defer { try? FileManager.default.removeItem(atPath: root) }

    let source = join(root, "source")
    try? FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
    write("x", to: join(source, "f.txt"))

    let dest = join(root, "dest")
    try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)

    var threwDestExists = false
    do {
        try CowCloner.clone(from: source, to: dest)
    } catch CowCloner.CowCloneError.destinationExists {
        threwDestExists = true
    } catch {
        assertTrue(false, "expected destinationExists, got \(error)")
    }
    assertTrue(threwDestExists, "clone into existing dest must throw destinationExists")
}

// MARK: - clone: temp cleanup on failure

func testCowCloneCleansUpTempOnFailure() {
    let root = makeTempDir("clone-fail")
    defer { try? FileManager.default.removeItem(atPath: root) }

    // Source does not exist → copyfile fails → temp must be cleaned up.
    let source = join(root, "does-not-exist")
    let dest = join(root, "dest")

    var threw = false
    do {
        try CowCloner.clone(from: source, to: dest)
    } catch {
        threw = true
    }
    assertTrue(threw, "cloning a missing source must throw")
    assertFalse(FileManager.default.fileExists(atPath: dest), "dest must not exist after failure")

    // No leftover `<dest>.tmp-*` siblings.
    let siblings = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
    let leftovers = siblings.filter { $0.hasPrefix("dest.tmp-") }
    assertEqual(leftovers.count, 0, "temp clone dir must be removed on failure")
}

// MARK: - classify

func testCowClonerClassify() {
    let root = makeTempDir("classify")
    defer { try? FileManager.default.removeItem(atPath: root) }

    // .git directory → fullRepo
    let repo = join(root, "repo")
    try? FileManager.default.createDirectory(atPath: join(repo, ".git"), withIntermediateDirectories: true)
    assertEqual(CowCloner.classify(path: repo), .fullRepo, ".git dir → fullRepo")

    // .git regular file → linkedWorktree
    let linked = join(root, "linked")
    try? FileManager.default.createDirectory(atPath: linked, withIntermediateDirectories: true)
    write("gitdir: /somewhere/.git/worktrees/x", to: join(linked, ".git"))
    assertEqual(CowCloner.classify(path: linked), .linkedWorktree, ".git file → linkedWorktree")

    // no .git → plainDirectory
    let plain = join(root, "plain")
    try? FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: true)
    assertEqual(CowCloner.classify(path: plain), .plainDirectory, "no .git → plainDirectory")
}

// MARK: - git fixup

func testCowClonerGitFixupNewBranch() async {
    let root = makeTempDir("fixup")
    defer { try? FileManager.default.removeItem(atPath: root) }

    let runner = GitCommandRunner()
    let repo = join(root, "repo")
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)

    do {
        _ = try await runner.run(in: repo, ["init", "-q"])
        write("v1", to: join(repo, "tracked.txt"))
        _ = try await runner.run(in: repo, ["add", "tracked.txt"])
        _ = try await runner.run(in: repo, [
            "-c", "user.email=t@example.com", "-c", "user.name=Tester",
            "commit", "-q", "-m", "initial",
        ])

        // Dirty the tracked file (unstaged) and add an untracked file.
        write("v2-dirty", to: join(repo, "tracked.txt"))
        write("keep", to: join(repo, "untracked.txt"))

        // Inherited stale worktree registration that fixup must remove.
        let staleWorktrees = join(repo, ".git/worktrees/stale")
        try? FileManager.default.createDirectory(atPath: staleWorktrees, withIntermediateDirectories: true)
    } catch {
        assertTrue(false, "git setup failed (is git installed?): \(error)")
        return
    }

    // Clone the repo working tree (copies dirty tracked + untracked + .git).
    let clone = join(root, "clone")
    do {
        try CowCloner.clone(from: repo, to: clone)
    } catch {
        assertTrue(false, "clone of repo failed: \(error)")
        return
    }
    assertEqual(CowCloner.classify(path: clone), .fullRepo, "clone of repo is a fullRepo")

    do {
        try await CowCloner.gitFixup(
            clonePath: clone,
            branch: "feature",
            createBranch: true,
            baseBranch: nil,
            runner: runner
        )
    } catch {
        assertTrue(false, "gitFixup failed: \(error)")
        return
    }

    // -f reset tracked dirt back to the committed content.
    assertEqual(read(join(clone, "tracked.txt")), "v1", "tracked dirt reset by checkout -f")
    // Untracked file preserved — the whole point of the feature.
    assertEqual(read(join(clone, "untracked.txt")), "keep", "untracked file preserved")
    // Inherited stale worktree registrations removed.
    assertFalse(
        FileManager.default.fileExists(atPath: join(clone, ".git/worktrees")),
        ".git/worktrees removed by fixup"
    )
    // On the new branch.
    let branch = (try? await runner.run(in: clone, ["rev-parse", "--abbrev-ref", "HEAD"]))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    assertEqual(branch, "feature", "checked out new branch")
}
