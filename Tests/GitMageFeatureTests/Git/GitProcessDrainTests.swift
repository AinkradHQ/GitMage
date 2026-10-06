import Foundation
import Testing

@testable import GitMageFeature

/// `PipeDrain` is private to `GitRepositoryClient.swift`, so it is pinned through
/// the only thing that uses it: a real `git show` whose output is larger than the
/// pipe buffer (64 KB) and larger than the retained cap (32 MB).
@Suite("Git Mage — process output draining")
struct GitProcessDrainTests {

    @Test("Output well past the 64 KB pipe buffer returns whole instead of deadlocking", .timeLimit(.minutes(1)))
    func largerThanThePipeBuffer() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let lines = (1...20_000).map { "line \($0) of a file bigger than the pipe buffer" }
        try repo.write("big.txt", lines.joined(separator: "\n") + "\n")
        try repo.run("git", "add", "-A")
        try repo.run("git", "commit", "-qm", "big")
        let sha = try repo.run("git", "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let diff = try await GitRepositoryClient().loadCommitDiff(sha: sha, in: repo.path)

        #expect(diff.body.utf8.count > 500_000)
        #expect(diff.body.contains("+line 1 of a file"))
        #expect(diff.body.contains("+line 20000 of a file"), "the tail survives, nothing was cut")
        #expect(!diff.body.contains("output truncated"))
    }

    @Test("Output past 32 MB is cut and says so in-band", .timeLimit(.minutes(2)))
    func truncatesAt32MB() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let line = String(repeating: "x", count: 79) + "\n"
        let blob = Data(String(repeating: line, count: 33 * 1_048_576 / 80 + 1).utf8)  // ~33 MB
        try blob.write(to: URL(fileURLWithPath: repo.path + "/huge.txt"))
        try repo.run("git", "add", "-A")
        try repo.run("git", "commit", "-qm", "huge")
        let sha = try repo.run("git", "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let diff = try await GitRepositoryClient().loadCommitDiff(sha: sha, in: repo.path)

        #expect(diff.body.hasSuffix("… [output truncated at 32 MB]"))
        #expect(diff.body.utf8.count <= GitRepositoryClient.maxOutputBytes + 100)
        #expect(diff.body.utf8.count > GitRepositoryClient.maxOutputBytes - 1_000, "it keeps up to the cap, not less")
    }

    @Test("The caps are 32 MB of output and 256 KB of error text")
    func caps() {
        #expect(GitRepositoryClient.maxOutputBytes == 33_554_432)
        #expect(GitRepositoryClient.maxErrorBytes == 262_144)
    }

    @Test("A failing command surfaces its stderr text, trimmed")
    func failureCarriesStderr() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        do {
            _ = try await GitRepositoryClient().loadCommitDiff(sha: "deadbeef", in: repo.path)
            Issue.record("expected a failure")
        } catch let GitRepositoryError.commandFailed(message) {
            #expect(!message.isEmpty)
            #expect(message == message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
