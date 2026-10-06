import Foundation

extension GitRepositoryClient {
    /// The blocking spawn. Runs on `gitQueue`, never on the actor's executor.
    /// `nonisolated static` so it cannot accidentally touch actor state.
    nonisolated static func runGitBlocking(
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
            throw GitRepositoryError.commandFailed(
                errorOutput.isEmpty ? "git \(arguments.joined(separator: " ")) failed" : errorOutput)
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
///
/// `@unchecked Sendable`: the retained bytes are only touched under `lock`, and
/// the drain itself runs on this instance's own serial `queue`.
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
                    truncated = true  // keep draining, stop retaining
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
