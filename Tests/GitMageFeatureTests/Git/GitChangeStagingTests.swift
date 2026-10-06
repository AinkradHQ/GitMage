import XCTest

@testable import GitMageFeature

final class GitChangeStagingTests: XCTestCase {
    private func change(_ code: String, kind: GitChangeKind = .modified) -> GitChange {
        GitChange(id: code, path: "f", filePath: "f", sourcePath: nil, statusCode: code, kind: kind)
    }
    func testStagedOnly() {
        let c = change("M ")
        XCTAssertTrue(c.hasStagedComponent)
        XCTAssertFalse(c.hasUnstagedComponent)
    }
    func testUnstagedOnly() {
        let c = change(" M")
        XCTAssertFalse(c.hasStagedComponent)
        XCTAssertTrue(c.hasUnstagedComponent)
    }
    func testBothMM() {
        let c = change("MM")
        XCTAssertTrue(c.hasStagedComponent)
        XCTAssertTrue(c.hasUnstagedComponent)
    }
    func testUntracked() {
        let c = change("??", kind: .untracked)
        XCTAssertFalse(c.hasStagedComponent)
        XCTAssertTrue(c.hasUnstagedComponent)
    }
    func testAddedStaged() {
        let c = change("A ")
        XCTAssertTrue(c.hasStagedComponent)
        XCTAssertFalse(c.hasUnstagedComponent)
    }
    func testIgnored() {
        let c = change("!!", kind: .ignored)
        XCTAssertFalse(c.hasStagedComponent)
        XCTAssertFalse(c.hasUnstagedComponent)
    }
}
