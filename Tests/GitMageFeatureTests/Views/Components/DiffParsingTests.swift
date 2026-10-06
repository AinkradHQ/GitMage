import Foundation
import Testing

@testable import GitMageFeature

/// Characterisation of the diff parsers behind the History, Stash and Worktree
/// detail panes (`DiffFileSplitter`) and the line-numbered view (`DiffView.parse`).
@Suite("Git Mage — diff file splitter")
struct DiffFileSplitterTests {

    private let twoFiles = """
        commit abc123
        Author: Ada

            Message that mentions diff --git only mid-line

        diff --git a/old.txt b/new.txt
        similarity index 90%
        rename from old.txt
        rename to new.txt
        diff --git a/added.txt b/added.txt
        new file mode 100644
        --- /dev/null
        +++ b/added.txt
        @@ -0,0 +1 @@
        +hi
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -bye
        """

    @Test("The commit-message preamble is dropped and each file becomes one slice")
    func splitsPerFile() {
        let files = DiffFileSplitter.split(twoFiles)
        #expect(files.map(\.filename) == ["new.txt", "added.txt", "gone.txt"])
        #expect(files.allSatisfy { $0.patch?.hasPrefix("diff --git ") == true })
        #expect(files.first?.patch?.contains("Author: Ada") == false)
    }

    @Test("Status is read from the rename, new file and deleted file headers")
    func statuses() {
        #expect(DiffFileSplitter.split(twoFiles).map(\.status) == ["renamed", "added", "removed"])
    }

    @Test("A plain modification has status modified, and ids carry the file index")
    func modifiedAndIDs() {
        let body = "diff --git a/m.txt b/m.txt\nindex 1..2 100644\n--- a/m.txt\n+++ b/m.txt\n@@ -1 +1 @@\n-a\n+b"
        let files = DiffFileSplitter.split(body + "\n" + body)
        #expect(files.map(\.status) == ["modified", "modified"])
        #expect(files.map(\.id) == ["0-m.txt", "1-m.txt"])
    }

    @Test("A +++ line wins over the header's last token, so a spaced name survives")
    func plusPlusPlusNamesTheFile() {
        let body = "diff --git a/my file b/my file\n--- a/my file\n+++ b/my file\n@@ -1 +1 @@\n-a\n+b"
        #expect(DiffFileSplitter.split(body).first?.filename == "my file")
    }

    @Test("Without a +++ line, a spaced name is cut to its last space-separated token")
    func spacedNameWithoutHunk() {
        let body = "diff --git a/my file b/my file\nsimilarity index 100%"
        #expect(DiffFileSplitter.split(body).first?.filename == "file")
    }

    @Test("A body with no file header comes back as one unnamed modified slice")
    func headerlessBody() {
        let files = DiffFileSplitter.split("just some text\nno diff here")
        #expect(files.count == 1)
        #expect(files.first?.filename == "")
        #expect(files.first?.status == "modified")
        #expect(files.first?.patch == "just some text\nno diff here")
    }

    @Test("An empty or whitespace-only body has no slices")
    func emptyBody() {
        #expect(DiffFileSplitter.split("").isEmpty)
        #expect(DiffFileSplitter.split("  \n\t\n").isEmpty)
    }
}

@Suite("Git Mage — diff line numbering")
struct DiffViewParseTests {

    @Test("Context, removed and added lines get the right old and new numbers")
    func lineNumbers() {
        let body = "@@ -10,3 +20,4 @@\n keep\n-gone\n+new one\n+new two\n tail"
        let rows = DiffView.parse(body)
        #expect(rows.map(\.kind) == [.hunk, .context, .remove, .add, .add, .context])
        #expect(rows.map(\.oldNo) == [nil, 10, 11, nil, nil, 12])
        #expect(rows.map(\.newNo) == [nil, 20, nil, 21, 22, 23])
        #expect(rows.map(\.text) == [body.components(separatedBy: "\n")[0], "keep", "gone", "new one", "new two", "tail"])
    }

    @Test("A second hunk restarts the numbers from its own header")
    func secondHunkResets() {
        let rows = DiffView.parse("@@ -1,1 +1,1 @@\n a\n@@ -50,1 +60,1 @@\n b")
        #expect(rows[1].oldNo == 1 && rows[1].newNo == 1)
        #expect(rows[3].oldNo == 50 && rows[3].newNo == 60)
    }

    @Test("A hunk header without a comma still sets the start line")
    func hunkWithoutCounts() {
        let rows = DiffView.parse("@@ -7 +9 @@\n x")
        #expect(rows[1].oldNo == 7 && rows[1].newNo == 9)
    }

    @Test("Everything before the first hunk is meta, even lines that look like content")
    func headersAreMeta() {
        let body = "diff --git a/f b/f\nindex 1..2\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b"
        let rows = DiffView.parse(body)
        #expect(rows.prefix(4).allSatisfy { $0.kind == .meta })
        #expect(rows.prefix(4).allSatisfy { $0.oldNo == nil && $0.newNo == nil })
        #expect(rows.map(\.kind).suffix(3) == [.hunk, .remove, .add])
    }

    @Test("Inside a hunk, a line starting --- or +++ is content, not a header")
    func dashesInsideAHunk() {
        let rows = DiffView.parse("@@ -1,2 +1,2 @@\n--- sql comment\n+++x")
        #expect(rows[1].kind == .remove)
        #expect(rows[1].text == "-- sql comment")
        #expect(rows[2].kind == .add)
        #expect(rows[2].text == "++x")
    }

    @Test("A no-newline marker is meta and does not advance either counter")
    func noNewlineMarker() {
        let rows = DiffView.parse("@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b")
        #expect(rows.map(\.kind) == [.hunk, .remove, .meta, .add])
        #expect(rows[3].newNo == 1)
    }

    @Test("A bare empty line inside a hunk is an empty context line that advances both counters")
    func emptyContextLine() {
        let rows = DiffView.parse("@@ -1,2 +1,2 @@\n\n x")
        #expect(rows[1].kind == .context)
        #expect(rows[1].text == "")
        #expect(rows[2].oldNo == 2 && rows[2].newNo == 2)
    }

    @Test("A new diff --git line closes the hunk, so its headers are meta again")
    func nextFileLeavesTheHunk() {
        let rows = DiffView.parse("@@ -1 +1 @@\n-a\ndiff --git a/g b/g\n--- a/g\n+++ b/g\n@@ -3 +3 @@\n+z")
        #expect(rows.map(\.kind) == [.hunk, .remove, .meta, .meta, .meta, .hunk, .add])
        #expect(rows.last?.newNo == 3)
    }

    @Test("Row ids are sequential and an empty body has no rows")
    func idsAndEmpty() {
        #expect(DiffView.parse("@@ -1 +1 @@\n a\n b").map(\.id) == [0, 1, 2])
        #expect(DiffView.parse("").isEmpty)
    }

    @Test("Tabs are expanded to four spaces for display only")
    func displayTextExpandsTabs() {
        let row = DiffView.Row(id: 0, kind: .context, oldNo: 1, newNo: 1, text: "\tx")
        #expect(DiffView.displayText(row) == "    x")
    }
}
