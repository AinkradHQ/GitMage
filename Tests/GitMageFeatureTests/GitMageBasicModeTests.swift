import Testing
import Foundation
import SwiftUI
import AinkradAppKit
@testable import GitMageFeature

/// Git Mage's basic mode — the app where the milestone's latency criterion
/// actually bites.
///
/// Run against a REAL temporary git repository rather than a stubbed client,
/// because the thing under test is which git subprocesses the load runs, and a
/// stub would happily agree with whatever the code does.
@Suite("Git Mage — basic mode")
@MainActor
struct GitMageBasicModeTests {

    @Test("Git Mage opts into modes, so the host's cast finds it")
    func optsIntoModes() {
        #expect((GitMageApp.self as Any) as? AinkradAppModes.Type != nil)
    }

    @Test("The full load is the default, so advanced is unaffected")
    func fullIsTheDefault() {
        // Basic mode opts IN. An app that forgot to set the scope must get the
        // old behaviour, not a silently truncated one.
        let model = GitMageViewModel(host: makeHost())
        #expect(model.loadScope == .full)
    }

    @Test("The basic load fills the branch list and the current branch")
    func basicLoadPopulatesBranches() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.run("git", "checkout", "-b", "feature/x")

        let model = makeModel(at: repo.path)
        model.loadScope = .basic
        model.refresh()
        try await settle(until: { !model.branches.isEmpty })

        #expect(model.branches.contains { $0.name == "feature/x" })
        #expect(model.branches.first { $0.isCurrent }?.name == "feature/x")
        #expect(model.selectedBranchName == "feature/x",
                "the switcher needs the current branch selected without a status call")
    }

    @Test("The basic load does NOT read the working tree, stashes or a diff")
    func basicLoadSkipsTheExpensiveWork() async throws {
        // The whole point of the mode. The full refresh runs `git status`,
        // `git stash list` and a diff of the first changed file — ~73ms of
        // which ~84% is process spawn — and basic mode shows none of it.
        // Trimming only the VIEW would have saved nothing.
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.write("dirty.txt", "uncommitted")
        try repo.run("git", "stash", "push", "--include-untracked")
        try repo.write("dirty.txt", "uncommitted again")

        let model = makeModel(at: repo.path)
        model.loadScope = .basic
        model.refresh()
        try await settle(until: { !model.branches.isEmpty })

        #expect(model.snapshot == nil, "basic must not run git status")
        #expect(model.stashes.isEmpty, "basic must not list stashes")
        #expect(model.diffSnapshot == nil, "basic must not load a diff")
    }

    @Test("The full load still reads all of it")
    func fullLoadIsUnchanged() async throws {
        // The counterpart: proving basic is narrow is only meaningful if
        // advanced is still wide.
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.write("dirty.txt", "uncommitted")

        let model = makeModel(at: repo.path)
        model.refresh()
        try await settle(until: { model.snapshot != nil })

        #expect(model.snapshot != nil)
        #expect(model.branches.isEmpty == false)
    }

    @Test("Switching basic -> advanced does not wipe what advanced loaded")
    func basicRefreshPreservesAdvancedState() async throws {
        // A pane keeps its model across a mode switch, so a basic refresh that
        // cleared `snapshot` would make every switch back look like a reload.
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.write("dirty.txt", "uncommitted")

        let model = makeModel(at: repo.path)
        model.refresh()
        try await settle(until: { model.snapshot != nil })

        model.loadScope = .basic
        model.refresh()
        try await settle(until: { !model.branches.isEmpty })

        #expect(model.snapshot != nil, "the basic load must not clear advanced's state")
    }

    // MARK: - Helpers

    private func makeHost() -> FakeHostServices {
        FakeHostServices(context: RecordingContextRegistry())
    }

    private func makeModel(at path: String) -> GitMageViewModel {
        let model = GitMageViewModel(host: makeHost())
        model.repos = [GitMageRepoConfig(id: path, path: path, name: "temp",
                                         draftCommitMessage: "", lastBranch: "")]
        model.activeRepoID = path
        return model
    }

    /// Polls rather than sleeping a fixed interval: the model's loads are
    /// `Task { @MainActor }`, so a fixed wait is either flaky or slow.
    private func settle(until condition: @MainActor () -> Bool,
                        timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("timed out waiting for the load to settle")
    }
}

/// A real git repository in a temp directory, with one commit.
private struct TempRepo {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitmage-basic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.path
        try run("git", "init", "-b", "main")
        // Identity is set locally so the test does not depend on the machine's
        // global git config, which may have none.
        try run("git", "config", "user.email", "test@example.com")
        try run("git", "config", "user.name", "Test")
        try write("README.md", "hello")
        try run("git", "add", "-A")
        try run("git", "commit", "-m", "initial")
    }

    func write(_ name: String, _ contents: String) throws {
        try contents.write(toFile: "\(path)/\(name)", atomically: true, encoding: .utf8)
    }

    @discardableResult
    func run(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
