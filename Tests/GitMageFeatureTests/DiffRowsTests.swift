import Foundation
import Testing
@testable import GitMageFeature

@Suite("DiffRows")
struct DiffRowsTests {
    private let sample = """
    @@ -1,4 +1,5 @@
     context line
    -removed line
    +added line one
    +added line two
     trailing context
    """

    @Test func countsAdditions() {
        #expect(DiffRows(body: sample, fontSize: 11).additions == 2)
    }

    @Test func countsDeletions() {
        #expect(DiffRows(body: sample, fontSize: 11).deletions == 1)
    }

    @Test func reportsTextualChanges() {
        #expect(DiffRows(body: sample, fontSize: 11).hasTextualChanges)
    }

    @Test func aMetaOnlyDiffHasNoTextualChanges() {
        let metaOnly = "diff --git a/x b/x\nsimilarity index 100%"
        #expect(!DiffRows(body: metaOnly, fontSize: 11).hasTextualChanges)
    }

    @Test func codeWidthScalesWithTheLongestLine() {
        let narrow = DiffRows(body: "@@ -1 +1 @@\n+ab", fontSize: 11)
        let wide = DiffRows(body: "@@ -1 +1 @@\n+" + String(repeating: "x", count: 200),
                            fontSize: 11)
        #expect(wide.codeWidth > narrow.codeWidth)
    }

    @Test func codeWidthHasAFloorSoAnEmptyDiffStillLaysOut() {
        #expect(DiffRows(body: "@@ -0,0 +0,0 @@", fontSize: 11).codeWidth >= 80)
    }

    @Test func anEmptyBodyProducesNoRowsAndDoesNotTrap() {
        let rows = DiffRows(body: "", fontSize: 11)
        #expect(rows.rows.isEmpty)
        #expect(!rows.hasTextualChanges)
        #expect(rows.additions == 0)
        #expect(rows.deletions == 0)
    }

    @Test func rowIdentifiersAreUniqueSoForEachDoesNotCollapseRows() {
        let rows = DiffRows(body: sample, fontSize: 11).rows
        #expect(Set(rows.map(\.id)).count == rows.count)
    }
}
