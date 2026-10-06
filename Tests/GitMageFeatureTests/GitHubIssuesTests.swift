import XCTest

@testable import GitMageFeature

final class GitHubIssuesTests: XCTestCase {
    private func provider(status: Int, body: String) -> GitHubProvider {
        StubURLProtocol.status = status
        StubURLProtocol.body = Data(body.utf8)
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        return GitHubProvider(token: "t", session: URLSession(configuration: c))
    }
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    func testListIssuesFiltersOutPullRequests() async throws {
        let p = provider(
            status: 200,
            body: """
                [{"number":1,"title":"Bug","state":"open","user":{"login":"a"},"labels":[{"name":"bug","color":"f00"}],"assignees":[],"comments":2},
                 {"number":2,"title":"A PR","state":"open","user":{"login":"b"},"labels":[],"assignees":[],"comments":0,"pull_request":{"url":"x"}}]
                """)
        let issues = try await p.listIssues(repo, state: .open)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.number, 1)
        XCTAssertEqual(issues.first?.labelNames, ["bug"])
        XCTAssertEqual(issues.first?.commentCount, 2)
    }

    func testCreateIssueSendsFieldsAndReturnsNumber() async throws {
        let p = provider(
            status: 201,
            body:
                "{\"number\":7,\"title\":\"New\",\"state\":\"open\",\"user\":{\"login\":\"a\"},\"labels\":[],\"assignees\":[],\"comments\":0}"
        )
        let n = try await p.createIssue(repo, title: "New", body: "desc", labels: ["bug"], assignees: ["a"])
        XCTAssertEqual(n, 7)
        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/repos/o/r/issues")
        let json = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "New")
        XCTAssertEqual(json?["labels"] as? [String], ["bug"])
        XCTAssertEqual(json?["assignees"] as? [String], ["a"])
    }

    func testSetLabelsPatches() async throws {
        let p = provider(
            status: 200,
            body:
                "{\"number\":7,\"title\":\"x\",\"state\":\"open\",\"user\":{\"login\":\"a\"},\"labels\":[],\"assignees\":[],\"comments\":0}"
        )
        try await p.setLabels(repo, number: 7, labels: ["bug", "p1"])
        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "PATCH")
        XCTAssertEqual(req.url?.path, "/repos/o/r/issues/7")
        let json = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["labels"] as? [String], ["bug", "p1"])
    }

    func testCloseIssuePatchesState() async throws {
        let p = provider(
            status: 200,
            body:
                "{\"number\":7,\"title\":\"x\",\"state\":\"closed\",\"user\":{\"login\":\"a\"},\"labels\":[],\"assignees\":[],\"comments\":0}"
        )
        try await p.setIssueState(repo, number: 7, state: .closed)
        let json = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["state"] as? String, "closed")
    }
}
