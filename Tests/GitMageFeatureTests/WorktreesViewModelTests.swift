import XCTest

@testable import GitMageFeature

@MainActor
final class WorktreesViewModelTests: XCTestCase {
    func testLoadAddOpenRemove() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()

        let f = repoURL.appendingPathComponent("README.md")
        try "hi\n".write(to: f, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "init", in: repoURL.path)

        // Git canonicalizes tmp paths (e.g. /var -> /private/var); resolve the same way
        // the client will so path comparisons in this test are apples-to-apples.
        let canonicalRoot = try canonicalToplevel(of: repoURL)

        var openedPath: String?
        let vm = WorktreesViewModel(
            client: client,
            repositoryPath: repoURL.path,
            currentRoot: canonicalRoot,
            branches: [],
            onOpen: { openedPath = $0 }
        )

        await vm.load()
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.worktrees.count, 1)
        XCTAssertTrue(vm.isCurrent(vm.worktrees[0]))

        let wtPath = canonicalRoot + "-wt"
        vm.addMode = .newBranch
        vm.addBranchName = "wt-branch"
        await vm.add(destination: wtPath)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.showAdd)
        XCTAssertEqual(vm.worktrees.count, 2)

        guard let added = vm.worktrees.first(where: { $0.path == wtPath }) else {
            return XCTFail("expected added worktree at \(wtPath), got \(vm.worktrees.map(\.path))")
        }
        XCTAssertEqual(added.branch, "wt-branch")
        XCTAssertFalse(vm.isCurrent(added))

        vm.open(added)
        XCTAssertEqual(openedPath, wtPath)

        await vm.remove(added, force: true)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.worktrees.count, 1)
        XCTAssertFalse(vm.worktrees.contains { $0.path == wtPath })
    }

    func testLoadGuardsEmptyRepositoryPath() async {
        let client = GitRepositoryClient()
        let vm = WorktreesViewModel(
            client: client,
            repositoryPath: "",
            currentRoot: "",
            branches: [],
            onOpen: { _ in }
        )
        await vm.load()
        XCTAssertTrue(vm.worktrees.isEmpty)
    }

    private func makeTemporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        return root
    }

    private func canonicalToplevel(of directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "WorktreesViewModelTests", code: Int(process.terminationStatus))
        }
    }
}
