import XCTest

@testable import GitMageFeature

/// Wave 1-B: `git status --short` C-quotes any path containing non-ASCII bytes,
/// a quote, a backslash or a control character. The parser used to take the
/// line remainder verbatim, so the resulting `filePath` was a path that does
/// not exist — and every later `git add` / `git checkout --` on it failed.
/// Staging and discarding were broken for any non-ASCII filename.
final class GitQuotedPathTests: XCTestCase {

    func testDecodesUTF8OctalEscapes() {
        // `é` is two UTF-8 bytes; decoding each escape separately gives mojibake.
        XCTAssertEqual(GitStatusParser.unquotePath("\"src/caf\\303\\251.txt\""), "src/café.txt")
        XCTAssertEqual(GitStatusParser.unquotePath("\"\\346\\227\\245\\346\\234\\254.md\""), "日本.md")
    }

    func testDecodesSimpleEscapes() {
        XCTAssertEqual(GitStatusParser.unquotePath("\"a\\\"b.txt\""), "a\"b.txt")
        XCTAssertEqual(GitStatusParser.unquotePath("\"a\\\\b.txt\""), "a\\b.txt")
        XCTAssertEqual(GitStatusParser.unquotePath("\"a\\tb.txt\""), "a\tb.txt")
    }

    func testLeavesUnquotedPathsAlone() {
        // Spaces alone do not trigger git's quoting, so this must pass through.
        XCTAssertEqual(GitStatusParser.unquotePath("my file.txt"), "my file.txt")
        XCTAssertEqual(GitStatusParser.unquotePath("src/main.swift"), "src/main.swift")
        XCTAssertEqual(GitStatusParser.unquotePath(""), "")
    }

    func testParsedChangeCarriesTheRealPath() throws {
        let change = try XCTUnwrap(firstChange(" M \"src/caf\\303\\251.txt\""))
        // This is the value handed to `git add` / `git checkout --`.
        XCTAssertEqual(change.filePath, "src/café.txt")
    }

    func testRenameSeparatorInsideAQuotedNameDoesNotSplit() throws {
        // A file literally named `a -> b` is legal. Splitting on it would
        // produce two paths, neither of which exists.
        let change = try XCTUnwrap(firstChange(" M \"a -> b.txt\""))
        XCTAssertEqual(change.filePath, "a -> b.txt")
        XCTAssertNil(change.sourcePath, "was misparsed as a rename")
    }

    func testRealRenameStillSplits() throws {
        let change = try XCTUnwrap(firstChange("R  old.txt -> new.txt"))
        XCTAssertEqual(change.sourcePath, "old.txt")
        XCTAssertEqual(change.filePath, "new.txt")
    }

    func testQuotedRenameDecodesBothSides() throws {
        let change = try XCTUnwrap(firstChange("R  \"caf\\303\\251.txt\" -> \"th\\303\\251.txt\""))
        XCTAssertEqual(change.sourcePath, "café.txt")
        XCTAssertEqual(change.filePath, "thé.txt")
    }

    /// `parse` expects the `--branch` header on line 1, so prepend one.
    private func firstChange(_ statusLine: String) -> GitChange? {
        GitStatusParser.parse(
            statusOutput: "## main\n" + statusLine,
            repositoryRoot: "/tmp/repo",
            lastCommitSummary: nil
        ).changes.first
    }
}
