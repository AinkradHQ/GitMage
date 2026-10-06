import XCTest

@testable import GitMageFeature

final class RemoteInfoParserTests: XCTestCase {
    func testParsesHttpsRemote() {
        let r = RemoteInfoParser.parse(remoteURL: "https://github.com/AhmedMElhalaby/GitMage.git")
        XCTAssertEqual(r, RepoRef(host: "github.com", owner: "AhmedMElhalaby", name: "GitMage"))
    }
    func testParsesScpRemote() {
        let r = RemoteInfoParser.parse(remoteURL: "git@github.com:AhmedMElhalaby/GitMage.git")
        XCTAssertEqual(r, RepoRef(host: "github.com", owner: "AhmedMElhalaby", name: "GitMage"))
    }
    func testParsesWithoutGitSuffixAndTrailingSlash() {
        let r = RemoteInfoParser.parse(remoteURL: "https://github.com/owner/repo/")
        XCTAssertEqual(r, RepoRef(host: "github.com", owner: "owner", name: "repo"))
    }
    func testRejectsMalformed() {
        XCTAssertNil(RemoteInfoParser.parse(remoteURL: "not-a-url"))
        XCTAssertNil(RemoteInfoParser.parse(remoteURL: "https://github.com/owner"))
    }
}
