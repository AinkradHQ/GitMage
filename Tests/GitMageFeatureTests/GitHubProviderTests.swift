import XCTest

@testable import GitMageFeature

final class GitHubProviderTests: XCTestCase {
    private func makeProvider(status: Int, body: String) -> GitHubProvider {
        StubURLProtocol.status = status
        StubURLProtocol.body = Data(body.utf8)
        StubURLProtocol.lastRequest = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return GitHubProvider(token: "t", session: URLSession(configuration: config))
    }
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    func testListPullRequestsParses() async throws {
        let p = makeProvider(
            status: 200,
            body: """
                [{"id":1,"number":7,"title":"Fix","state":"open","draft":false,
                  "user":{"login":"alice"},"head":{"ref":"feat"},"base":{"ref":"main"}}]
                """)
        let prs = try await p.listPullRequests(repo, state: .open)
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.number, 7)
        XCTAssertEqual(prs.first?.author, "alice")
        XCTAssertEqual(prs.first?.headBranch, "feat")
    }

    func testUnauthorizedMapsToForgeError() async {
        let p = makeProvider(status: 401, body: "{\"message\":\"Bad credentials\"}")
        do {
            _ = try await p.verify()
            XCTFail("expected throw")
        } catch let e as ForgeError { XCTAssertEqual(e, .unauthorized) } catch { XCTFail("wrong error") }
    }

    /// A 422 must carry GitHub's reason: "server 422" gives the caller nothing
    /// to act on and invites an identical retry.
    func testValidationFailureCarriesGitHubsReason() async {
        let p = makeProvider(
            status: 422,
            body: """
                {"message":"Validation Failed","errors":[{"resource":"PullRequest","field":"base",
                 "code":"invalid","message":"No commits between main and feat"}]}
                """)
        do {
            _ = try await p.createPullRequest(
                repo, title: "t", body: "b",
                head: "feat", base: "main", draft: false)
            XCTFail("expected throw")
        } catch let e as ForgeError {
            XCTAssertEqual(e, .invalidRequest("Validation Failed — No commits between main and feat"))
            XCTAssertEqual(e.errorDescription, "Validation Failed — No commits between main and feat")
        } catch { XCTFail("wrong error") }
    }

    /// The detail-less shape ("A pull request already exists for o:feat.") must
    /// still reach the caller rather than being dropped for lack of `errors`.
    func testValidationFailureWithoutErrorDetailsUsesTheTopLevelMessage() async {
        let p = makeProvider(status: 422, body: "{\"message\":\"A pull request already exists for o:feat.\"}")
        do {
            _ = try await p.createPullRequest(
                repo, title: "t", body: "b",
                head: "feat", base: "main", draft: false)
            XCTFail("expected throw")
        } catch let e as ForgeError {
            XCTAssertEqual(e, .invalidRequest("A pull request already exists for o:feat."))
        } catch { XCTFail("wrong error") }
    }

    func testSubmitReviewSendsEventInBody() async throws {
        let p = makeProvider(status: 200, body: "{}")
        try await p.submitReview(repo, number: 7, event: .approve, body: "LGTM")
        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.url?.path, "/repos/o/r/pulls/7/reviews")
        XCTAssertEqual(req.httpMethod, "POST")
        let sentBody = StubURLProtocol.lastBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: sentBody) as? [String: Any]
        XCTAssertEqual(json?["event"] as? String, "APPROVE")
        XCTAssertEqual(json?["body"] as? String, "LGTM")
    }

    func testMergeUsesMethodAndPutVerb() async throws {
        let p = makeProvider(status: 200, body: "{\"merged\":true}")
        try await p.merge(repo, number: 7, method: .squash)
        let req = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.url?.path, "/repos/o/r/pulls/7/merge")
        let json = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["merge_method"] as? String, "squash")
    }
}

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody =
            request.httpBody
            ?? request.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buf = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buf, maxLength: buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                }
                return data
            }
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
