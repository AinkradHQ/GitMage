import Foundation

enum GitRepositoryError: Error, LocalizedError, Equatable {
    case missingPath
    case pathDoesNotExist(String)
    case notARepository(String)
    case invalidCommitMessage
    case invalidBranchName
    case invalidTagName
    case invalidRemoteURL
    case nothingToCommit
    case detachedHead
    case commandFailed(String)
    /// An argument git would read as an option (or a transport helper) that
    /// this module did not author — see `GitArgumentGuard`.
    case unsafeArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "Select a repository path first."
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .invalidCommitMessage:
            return "Enter a non-empty commit message."
        case .invalidBranchName:
            return "Enter a non-empty branch name."
        case .invalidTagName:
            return "Enter a non-empty tag name."
        case .invalidRemoteURL:
            return "Enter a repository URL to clone."
        case .nothingToCommit:
            return "There are no staged changes to commit."
        case .detachedHead:
            return "You are not on a branch (detached HEAD). Check out a branch first."
        case .commandFailed(let message):
            return message
        case .unsafeArgument(let argument):
            return "Refused: \"\(argument)\" would be read by git as an option, not as a value."
        }
    }
}

actor GitRepositoryClient {
    /// Cache of picked path → resolved repository root, so routine actions don't
    /// re-run `rev-parse --show-toplevel` on every call.
    private var rootCache: [String: String] = [:]

    func isRepository(at path: String) async -> Bool {
        (try? await validateRepositoryPath(path)) != nil
    }

    func loadSnapshot(at path: String) async throws -> GitRepositorySnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        // Both read-only, so they share the concurrent lane and run together.
        // `GIT_OPTIONAL_LOCKS=0` stops `status` opportunistically rewriting the
        // index — that write is what could collide with a concurrent stage.
        async let status = runGit(["status", "--short", "--branch"], in: rootURL,
                                  environment: Self.noOptionalLocks, readOnly: true)
        async let summary = try? runGit(["log", "-1", "--pretty=format:%s"], in: rootURL, readOnly: true)
        let statusOutput = try await status
        let lastCommitSummary = await summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitStatusParser.parse(
            statusOutput: statusOutput,
            repositoryRoot: rootURL.path,
            lastCommitSummary: lastCommitSummary?.isEmpty == true ? nil : lastCommitSummary
        )
    }

    func loadBranches(at path: String) async throws -> [GitBranchSummary] {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit([
            "for-each-ref",
            "--format=%(HEAD)\t%(refname:short)\t%(upstream:short)\t%(upstream:trackshort)",
            "refs/heads"
        ], in: rootURL, readOnly: true)
        return GitBranchParser.parse(output: output)
    }

    func checkoutBranch(_ branchName: String, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["checkout", branchName], in: rootURL)
    }

    func stageAllChanges(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["add", "-A"], in: rootURL)
    }

    /// Unstages every staged change. Before the first commit there is no HEAD to
    /// reset against, so the whole index is cleared instead.
    func unstageAllChanges(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        if try await hasHead(in: rootURL) {
            _ = try await runGit(["reset"], in: rootURL)
        } else {
            _ = try await runGit(["rm", "-r", "--cached", "."], in: rootURL)
        }
    }

    func stage(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try await runGit(["add", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try await runGit(["add", change.filePath], in: rootURL)
        }
    }

    func unstage(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        guard change.canUnstage else { return }
        if try await !hasHead(in: rootURL) {
            if change.kind == .renamed, let sourcePath = change.sourcePath {
                _ = try await runGit(["rm", "--cached", "--", sourcePath, change.filePath], in: rootURL)
            } else {
                _ = try await runGit(["rm", "--cached", "--", change.filePath], in: rootURL)
            }
            return
        }

        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try await runGit(["restore", "--staged", "--", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try await runGit(["restore", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func discard(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        switch change.kind {
        case .untracked:
            _ = try await runGit(["clean", "-f", "--", change.filePath], in: rootURL)
        case .renamed:
            if let sourcePath = change.sourcePath {
                _ = try await runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", sourcePath, change.filePath], in: rootURL)
            } else {
                _ = try await runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
            }
        default:
            _ = try await runGit(["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func commit(message: String, in path: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidCommitMessage }

        let rootURL = try await repositoryRootURL(for: path)
        let staged = try await runGit(["diff", "--cached", "--name-only"], in: rootURL)
        guard !staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitRepositoryError.nothingToCommit
        }
        _ = try await runGit(["commit", "-m", trimmed], in: rootURL)
    }

    func createBranch(_ name: String, in path: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["checkout", "-b", trimmed], in: rootURL)
    }

    func fetch(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["fetch", "--all", "--prune"], in: rootURL)
    }

    /// Fast-forward-only pull. Surfaces git's error when the branch has diverged.
    func pull(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["pull", "--ff-only"], in: rootURL)
    }

    /// Pushes the current branch, setting `origin/<branch>` as upstream when none exists.
    func push(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        let branch = try await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard branch != "HEAD", !branch.isEmpty else { throw GitRepositoryError.detachedHead }

        let hasUpstream = (try? await runGit(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            in: rootURL
        )) != nil

        if hasUpstream {
            _ = try await runGit(["push"], in: rootURL)
        } else {
            _ = try await runGit(["push", "-u", "origin", branch], in: rootURL)
        }
    }

    func stashPush(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "push", "--include-untracked"], in: rootURL)
    }

    func stashPop(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "pop"], in: rootURL)
    }

    func stashApply(_ entry: GitStashEntry, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "apply", entry.id], in: rootURL)
    }

    func stashDrop(_ entry: GitStashEntry, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "drop", entry.id], in: rootURL)
    }

    func loadStashes(in path: String) async throws -> [GitStashEntry] {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(["stash", "list", "--format=%gd%x09%gs"], in: rootURL, readOnly: true)
        return GitStashParser.parse(output: output)
    }

    /// Initializes a plain directory as a new git repository.
    func initRepository(at path: String) async throws {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitRepositoryError.pathDoesNotExist(path)
        }
        _ = try await runGit(["init"], in: URL(fileURLWithPath: expanded, isDirectory: true))
        rootCache[path] = nil
    }

    /// Clones `remoteURL` into `parentDirectory` and returns the new repository path.
    func clone(remoteURL: String, into parentDirectory: String) async throws -> String {
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw GitRepositoryError.invalidRemoteURL }
        // Transport allowlist. `runGit`'s guard already blocks `ext::` and
        // leading-dash options, but a clone URL selects a *transport*, and git
        // will happily invoke any `git-remote-<helper>` on PATH for a scheme it
        // doesn't recognise. Checking here names the real constraint at the one
        // place a URL enters the system.
        if let rejected = GitArgumentGuard.rejectedCloneURL(trimmedURL) {
            throw GitRepositoryError.unsafeArgument(rejected)
        }

        let parentExpanded = (parentDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentExpanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitRepositoryError.pathDoesNotExist(parentDirectory)
        }

        let parentURL = URL(fileURLWithPath: parentExpanded, isDirectory: true)
        let destinationURL = parentURL.appendingPathComponent(
            GitRepositoryClient.repositoryName(fromRemote: trimmedURL),
            isDirectory: true
        )
        _ = try await runGit(["clone", trimmedURL, destinationURL.path], in: parentURL)
        return destinationURL.path
    }

    static func repositoryName(fromRemote remote: String) -> String {
        var trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        let separators = CharacterSet(charactersIn: "/:")
        let components = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
        return components.last ?? "repository"
    }

    func loadDiff(for change: GitChange, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let title = change.kind == .renamed ? "\(change.sourcePath ?? change.path) → \(change.filePath)" : change.filePath

        let arguments: [String]
        switch change.kind {
        case .untracked:
            arguments = ["diff", "--no-index", "--", "/dev/null", change.filePath]
        case .renamed:
            let pathspecs = change.sourcePath.map { [$0, change.filePath] } ?? [change.filePath]
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--"] + pathspecs
                : ["diff", "--no-ext-diff", "--unified=3", "--"] + pathspecs
        case .deleted:
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        default:
            arguments = change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        }

        let output = try await runGit(
            arguments,
            in: rootURL,
            acceptedExitCodes: change.kind == .untracked ? [0, 1] : [0]
        )

        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: title,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }

    /// Total number of commits reachable from HEAD (0 before the first commit).
    func commitCount(in path: String) async throws -> Int {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return 0 }
        let output = try await runGit(["rev-list", "--count", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    /// Commits with parent SHAs, for the commit-graph view.
    func loadGraphCommits(limit: Int, in path: String) async throws -> [GraphCommit] {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return [] }
        let sep = "\u{1f}"
        let output = try await runGit([
            "log",
            "--topo-order",
            "--max-count=\(max(1, limit))",
            "--pretty=format:%H\(sep)%h\(sep)%s\(sep)%an\(sep)%ar\(sep)%P"
        ], in: rootURL)
        return GitGraphParser.parse(output)
    }

    func loadLog(skip: Int = 0, limit: Int, in path: String) async throws -> [GitCommitSummary] {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return [] }
        let output = try await runGit([
            "log",
            "--skip=\(max(0, skip))",
            "--max-count=\(max(1, limit))",
            "--pretty=format:%H%x09%h%x09%s%x09%an%x09%ar"
        ], in: rootURL)
        return GitLogParser.parse(output: output)
    }

    func remoteInfo(in path: String) async throws -> RepoRef? {
        let rootURL = try await repositoryRootURL(for: path)
        let url = (try? await runGit(["remote", "get-url", "origin"], in: rootURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url, !url.isEmpty else { return nil }
        return RemoteInfoParser.parse(remoteURL: url)
    }

    func loadWorktrees(in path: String) async throws -> [GitWorktree] {
        let rootURL = try await repositoryRootURL(for: path)
        let out = try await runGit(["worktree", "list", "--porcelain"], in: rootURL)
        return GitWorktreeParser.parse(porcelain: out)
    }

    func addWorktree(path: String, base: WorktreeBase, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.pathDoesNotExist(path) }
        var args = ["worktree", "add"]
        switch base {
        case .newBranch(let name):      args += ["-b", name, trimmed]
        case .existingBranch(let name): args += [trimmed, name]
        case .detached(let ref):        args += ["--detach", trimmed, ref]
        }
        _ = try await runGit(args, in: rootURL)
    }

    func removeWorktree(path: String, force: Bool, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        _ = try await runGit(args, in: rootURL)
    }

    func pruneWorktrees(in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        _ = try await runGit(["worktree", "prune"], in: rootURL)
    }

    func lockWorktree(path: String, reason: String?, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        var args = ["worktree", "lock"]
        if let reason, !reason.isEmpty { args += ["--reason", reason] }
        args.append(path)
        _ = try await runGit(args, in: rootURL)
    }

    func unlockWorktree(path: String, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        _ = try await runGit(["worktree", "unlock", path], in: rootURL)
    }

    func loadCommitDiff(sha: String, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(
            ["show", "--no-color", "--no-ext-diff", "--unified=3", "--format=medium", sha],
            in: rootURL
        )
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: sha,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }

    func stashDiff(_ id: String, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(
            ["stash", "show", "-p", "--no-color", "--no-ext-diff", "--unified=3", id],
            in: rootURL
        )
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: id,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }

    func deleteBranch(_ name: String, in path: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["branch", "-d", trimmed], in: rootURL)   // safe delete; refuses unmerged
    }

    /// The repository ROOT for `path` — `rev-parse --show-toplevel` already
    /// answers both "is this a repo" and "where is its root", so one spawn does both.
    private func validateRepositoryPath(_ path: String) async throws -> URL {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitRepositoryError.missingPath
        }

        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            throw GitRepositoryError.pathDoesNotExist(path)
        }

        let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
        do {
            let root = try await runGit(["rev-parse", "--show-toplevel"], in: url, readOnly: true)
            return URL(fileURLWithPath: root.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw GitRepositoryError.notARepository(path)
        }
    }

    func repositoryRootURL(for path: String) async throws -> URL {
        if let cached = rootCache[path] {
            return URL(fileURLWithPath: cached)
        }
        let rootURL = try await validateRepositoryPath(path)
        rootCache[path] = rootURL.path
        return rootURL
    }

    /// Drops the cached root, so the next call re-validates. For a refresh that
    /// failed: the folder may have moved or stopped being a repository.
    func forgetRoot(for path: String) {
        rootCache[path] = nil
    }

    func hasHead(in repositoryURL: URL) async throws -> Bool {
        do {
            _ = try await runGit(["rev-parse", "--verify", "HEAD"], in: repositoryURL)
            return true
        } catch {
            return false
        }
    }

    /// Cap on retained stdout per git invocation. Generous enough for any diff
    /// a human will read, small enough that a runaway `git diff` on a binary
    /// blob can't exhaust memory.
    static let maxOutputBytes = 32 * 1_048_576
    /// stderr is diagnostics; a few hundred KB is already more than anyone reads.
    static let maxErrorBytes = 256 * 1024

    /// A serial queue owning every `git` invocation.
    ///
    /// `runGit` blocks for as long as git runs, and `git clone`, `git fetch` or
    /// a large `git log` are seconds, not milliseconds. Running that
    /// synchronously on the actor's executor blocks a **cooperative pool**
    /// thread — a pool sized to the core count and shared by every async task
    /// in the process, including the host's. Enough concurrent git work and
    /// unrelated `await`s stop making progress.
    ///
    /// Moving the blocking part to a dedicated queue and suspending the actor
    /// on a continuation frees the cooperative thread for the duration. The
    /// queue stays serial: git operations on one repo must not interleave, and
    /// this preserves the ordering the actor already guaranteed.
    /// Serial: every command that can write (the index, refs, the worktree), so
    /// two actions never race git's `index.lock`.
    private static let gitQueue = DispatchQueue(label: "com.ainkrad.gitmage.git", qos: .userInitiated)
    /// Concurrent: read-only commands, so a refresh's loads run side by side
    /// instead of paying one spawn after another.
    private static let readQueue = DispatchQueue(label: "com.ainkrad.gitmage.git.read",
                                                 qos: .userInitiated, attributes: .concurrent)
    static let noOptionalLocks = ["GIT_OPTIONAL_LOCKS": "0"]

    /// Commands spawned by this client — observable by tests.
    private(set) var spawnCount = 0

    /// Runs `git` with `arguments`, suspending rather than blocking.
    func runGit(
        _ arguments: [String],
        in repositoryURL: URL,
        acceptedExitCodes: Set<Int32> = [0],
        environment: [String: String]? = nil,
        readOnly: Bool = false
    ) async throws -> String {
        // Validate before leaving the actor — a rejected argument must never
        // reach the spawn path at all.
        if let rejected = GitArgumentGuard.rejectedArgument(in: arguments) {
            throw GitRepositoryError.unsafeArgument(rejected)
        }
        spawnCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            (readOnly ? Self.readQueue : Self.gitQueue).async {
                do {
                    continuation.resume(returning: try Self.runGitBlocking(
                        arguments, in: repositoryURL,
                        acceptedExitCodes: acceptedExitCodes, environment: environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The blocking spawn. Runs on `gitQueue`, never on the actor's executor.
    /// `nonisolated static` so it cannot accidentally touch actor state.
    private nonisolated static func runGitBlocking(
        _ arguments: [String],
        in repositoryURL: URL,
        acceptedExitCodes: Set<Int32>,
        environment: [String: String]?
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repositoryURL.path] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        if let environment {
            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment
        }

        do {
            try process.run()
        } catch {
            throw GitRepositoryError.commandFailed("Unable to launch git: \(error.localizedDescription)")
        }

        // Drain BOTH pipes on background queues BEFORE waiting for exit.
        //
        // This ordering is the whole fix. The previous code ran
        // `waitUntilExit()` and only then read the pipes — so as soon as git
        // produced more than the ~64KB pipe buffer, the child blocked writing,
        // the parent blocked waiting for a child that could never exit, and
        // because `runGit` is synchronous on this actor, the actor itself died
        // with it. `GitMageRuntime.sharedClient` is that actor, and the agent's
        // `git_op` tool goes through it, so a single `git show` on a real
        // commit wedged git support for the whole host until quit.
        //
        // (Reproduced directly: the same run/wait/read sequence emitting ~1MB
        // never returned and had to be SIGKILLed.)
        let outCollector = PipeDrain(handle: stdout.fileHandleForReading, limit: Self.maxOutputBytes)
        let errCollector = PipeDrain(handle: stderr.fileHandleForReading, limit: Self.maxErrorBytes)
        outCollector.start()
        errCollector.start()

        process.waitUntilExit()

        let (outData, outTruncated) = outCollector.finish()
        let (errData, _) = errCollector.finish()
        var output = String(decoding: outData, as: UTF8.self)
        let errorOutput = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard acceptedExitCodes.contains(process.terminationStatus) else {
            throw GitRepositoryError.commandFailed(errorOutput.isEmpty ? "git \(arguments.joined(separator: " ")) failed" : errorOutput)
        }

        if outTruncated {
            // A cap is necessary as well as a drain: `git diff` on a vendored
            // tree or a binary blob can be hundreds of megabytes, and holding
            // that as a Swift `String` to render in a pane is its own outage.
            // Say so in-band rather than silently returning a partial diff that
            // looks complete.
            output += "\n… [output truncated at \(Self.maxOutputBytes / 1_048_576) MB]\n"
        }
        return output
    }
}

/// Reads one end of a pipe to EOF on a background queue.
///
/// Exists so `runGit` can consume stdout and stderr *concurrently with* the
/// child process rather than after it — see the comment at the call site.
/// `limit` bounds how much is retained; bytes past the limit are read and
/// discarded, which keeps the child unblocked (the deadlock returns the moment
/// anything stops reading) while bounding memory.
private final class PipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let limit: Int
    private let queue: DispatchQueue
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    init(handle: FileHandle, limit: Int) {
        self.handle = handle
        self.limit = limit
        self.queue = DispatchQueue(label: "com.ainkrad.gitmage.pipe-drain")
    }

    func start() {
        queue.async(group: group) { [self] in
            while true {
                // `availableData` returns empty exactly at EOF, i.e. when the
                // child's write end closes.
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.lock()
                if data.count < limit {
                    let room = limit - data.count
                    data.append(chunk.count <= room ? chunk : chunk.prefix(room))
                    if chunk.count > room { truncated = true }
                } else {
                    truncated = true   // keep draining, stop retaining
                }
                lock.unlock()
            }
        }
    }

    /// Blocks until EOF, then returns what was retained.
    func finish() -> (Data, Bool) {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}
