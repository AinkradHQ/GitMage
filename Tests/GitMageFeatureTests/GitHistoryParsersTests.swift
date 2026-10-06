import Foundation
import Testing

@testable import GitMageFeature

/// Characterisation of the History-area parsers: pins today's output so the
/// GM-3 file moves cannot change it silently.
@Suite("Git Mage — log and stash parsers")
struct GitLogAndStashParserTests {

    @Test("A log line splits into sha, short sha, summary, author and relative date")
    func logLine() {
        let out = "a1b2c3\ta1b\tFix the thing\tAda\t2 days ago"
        #expect(
            GitLogParser.parse(output: out) == [
                GitCommitSummary(
                    id: "a1b2c3", shortSHA: "a1b", summary: "Fix the thing", author: "Ada", relativeDate: "2 days ago")
            ])
    }

    @Test("Blank lines and lines with fewer than five fields are dropped")
    func logDropsShortLines() {
        let out = "\nonly\tthree\tfields\n\nb\tb1\ts\tA\t1 day ago\n"
        let parsed = GitLogParser.parse(output: out)
        #expect(parsed.map(\.id) == ["b"])
    }

    @Test("An extra tab lands in the last field, because the split caps at five")
    func logExtraTabJoinsTheDate() {
        let parsed = GitLogParser.parse(output: "s\tsh\tsummary\tAda\t2 days\tago")
        #expect(parsed.first?.relativeDate == "2 days\tago")
        #expect(parsed.first?.author == "Ada")
    }

    @Test("Log order is preserved and an empty summary is kept")
    func logOrderAndEmptyFields() {
        let parsed = GitLogParser.parse(output: "1\t1\t\tA\tnow\n2\t2\tsecond\tB\tearlier")
        #expect(parsed.map(\.id) == ["1", "2"])
        #expect(parsed.first?.summary == "")
    }

    @Test("An empty log parses to nothing")
    func logEmpty() {
        #expect(GitLogParser.parse(output: "").isEmpty)
    }

    @Test("A stash line splits into its ref and message")
    func stashLine() {
        let parsed = GitStashParser.parse(output: "stash@{0}\tWIP on main: abc1234 hello")
        #expect(parsed == [GitStashEntry(id: "stash@{0}", index: 0, message: "WIP on main: abc1234 hello")])
    }

    @Test("A stash line with no tab uses its ref as the message")
    func stashWithoutMessage() {
        #expect(GitStashParser.parse(output: "stash@{0}").first?.message == "stash@{0}")
    }

    @Test("A message keeps its own tabs, because the split caps at two")
    func stashMessageKeepsTabs() {
        #expect(GitStashParser.parse(output: "stash@{0}\ta\tb").first?.message == "a\tb")
    }

    @Test("Index counts every non-blank line, including one dropped for an empty ref")
    func stashIndexSkipsDroppedLines() {
        let parsed = GitStashParser.parse(output: "stash@{0}\tone\n\tno ref\nstash@{2}\tthree")
        #expect(parsed.map(\.id) == ["stash@{0}", "stash@{2}"])
        #expect(parsed.map(\.index) == [0, 2])
    }

    @Test("An empty stash list parses to nothing")
    func stashEmpty() {
        #expect(GitStashParser.parse(output: "").isEmpty)
    }
}

@Suite("Git Mage — commit graph parser and layout")
struct GitGraphTests {
    private let sep = "\u{1f}"

    @Test("A graph line splits into six fields with space-joined parents")
    func graphLine() {
        let line = ["abc", "ab", "Merge it", "Ada", "1 hour ago", "p1 p2"].joined(separator: sep)
        let commit = GitGraphParser.parse(line).first
        #expect(commit?.sha == "abc")
        #expect(commit?.shortSHA == "ab")
        #expect(commit?.summary == "Merge it")
        #expect(commit?.author == "Ada")
        #expect(commit?.relativeDate == "1 hour ago")
        #expect(commit?.parents == ["p1", "p2"])
    }

    @Test("A root commit has an empty parent field, and a five-field line has no parents")
    func graphWithoutParents() {
        let root = ["r", "r1", "root", "A", "now", ""].joined(separator: sep)
        let five = ["s", "s1", "five", "A", "now"].joined(separator: sep)
        let parsed = GitGraphParser.parse(root + "\n" + five)
        #expect(parsed.map(\.sha) == ["r", "s"])
        #expect(parsed.allSatisfy { $0.parents.isEmpty })
    }

    @Test("Lines with fewer than five fields and blank lines are dropped")
    func graphDropsShortLines() {
        let ok = ["k", "k1", "ok", "A", "now", "p"].joined(separator: sep)
        #expect(GitGraphParser.parse("a\(sep)b\(sep)c\n\n" + ok).map(\.sha) == ["k"])
    }

    @Test("A linear history stays in column 0 and each row's before is the previous after")
    func linearLayout() {
        let rows = GitGraphBuilder.build([commit("C", ["B"]), commit("B", ["A"]), commit("A", [])])
        #expect(rows.map(\.col) == [0, 0, 0])
        #expect(rows.map(\.after) == [["B"], ["A"], []])
        #expect(rows.map(\.before) == [[], ["B"], ["A"]])
    }

    @Test("A merge opens a second lane that the branch tip then closes")
    func mergeLayout() {
        let rows = GitGraphBuilder.build([
            commit("M", ["A", "B"]), commit("A", ["R"]), commit("B", ["R"]), commit("R", []),
        ])
        #expect(rows.map(\.col) == [0, 0, 1, 0])
        #expect(rows[0].after == ["A", "B"])
        #expect(rows[1].after == ["R", "B"])
        #expect(rows[2].before == ["R", "B"])
        #expect(rows[2].after == ["R"], "R is already tracked, so B adds no duplicate lane")
        #expect(rows[3].after.isEmpty)
        #expect(rows[0].laneCount == 2)
    }

    @Test("A second head with a shared parent takes a new lane")
    func twoHeads() {
        let rows = GitGraphBuilder.build([commit("X", ["R"]), commit("Y", ["R"]), commit("R", [])])
        #expect(rows.map(\.col) == [0, 1, 0])
        #expect(rows[1].before == ["R"])
        #expect(rows[1].after == ["R"])
    }

    @Test("Lanes connect: each row's before equals the previous row's after")
    func lanesConnect() {
        let rows = GitGraphBuilder.build([
            commit("M", ["A", "B"]), commit("A", ["R"]), commit("B", ["R"]), commit("R", []),
        ])
        for (previous, next) in zip(rows, rows.dropFirst()) { #expect(next.before == previous.after) }
    }

    @Test("No commits lay out to no rows")
    func emptyLayout() {
        #expect(GitGraphBuilder.build([]).isEmpty)
    }

    private func commit(_ sha: String, _ parents: [String]) -> GraphCommit {
        GraphCommit(sha: sha, shortSHA: sha, summary: sha, author: "A", relativeDate: "now", parents: parents)
    }
}
