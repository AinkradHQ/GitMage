import XCTest

@testable import GitMageFeature

final class GitStatusParserTests: XCTestCase {
    func testParsesBranchAndChanges() {
        let output = """
            ## main...origin/main [ahead 2, behind 1]
             M Sources/App.swift
            ?? Notes/todo.md
            R  Old.swift -> New.swift
            """

        let snapshot = GitStatusParser.parse(
            statusOutput: output,
            repositoryRoot: "/tmp/repo",
            lastCommitSummary: "Refine repo inspector"
        )

        XCTAssertEqual(snapshot.branchName, "main")
        XCTAssertEqual(snapshot.upstream, "origin/main")
        XCTAssertEqual(snapshot.aheadCount, 2)
        XCTAssertEqual(snapshot.behindCount, 1)
        XCTAssertEqual(snapshot.lastCommitSummary, "Refine repo inspector")
        XCTAssertEqual(snapshot.changes.count, 3)
        XCTAssertEqual(snapshot.changes[0].kind, .modified)
        XCTAssertEqual(snapshot.changes[1].kind, .untracked)
        XCTAssertEqual(snapshot.changes[2].kind, .renamed)
        XCTAssertEqual(snapshot.changes[2].filePath, "New.swift")
        XCTAssertEqual(snapshot.changes[2].sourcePath, "Old.swift")
    }

    func testParsesNoCommitsHeader() {
        let snapshot = GitStatusParser.parse(
            statusOutput: "## No commits yet on develop\n?? README.md",
            repositoryRoot: "/tmp/repo",
            lastCommitSummary: nil
        )

        XCTAssertEqual(snapshot.branchName, "develop")
        XCTAssertNil(snapshot.upstream)
        XCTAssertEqual(snapshot.changes.first?.kind, .untracked)
    }

    func testParsesBranches() {
        let output = """
            *\tmain\torigin/main\t[ahead 1]
             \tfeature/login\t\t
             \trelease/1.0\torigin/release/1.0\t[behind 2]
            """

        let branches = GitBranchParser.parse(output: output)

        XCTAssertEqual(branches.first?.name, "main")
        XCTAssertEqual(branches.first?.isCurrent, true)
        XCTAssertEqual(branches[1].name, "feature/login")
        XCTAssertEqual(branches[2].tracking, "[behind 2]")
    }
}
