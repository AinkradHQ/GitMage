import Foundation

actor GitRepositoryClient {
    /// Cache of picked path → resolved repository root, so routine actions don't
    /// re-run `rev-parse --show-toplevel` on every call.
    var rootCache: [String: String] = [:]

    func isRepository(at path: String) async -> Bool {
        (try? await validateRepositoryPath(path)) != nil
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
    private static let readQueue = DispatchQueue(
        label: "com.ainkrad.gitmage.git.read",
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
                    continuation.resume(
                        returning: try Self.runGitBlocking(
                            arguments, in: repositoryURL,
                            acceptedExitCodes: acceptedExitCodes, environment: environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
