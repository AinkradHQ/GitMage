import Testing

@testable import GitMageFeature

@Suite("OverlaySelection")
struct OverlaySelectionTests {
    private let names = ["Main", "feature/x", "Fix"]

    @Test("A blank or whitespace query keeps every item")
    func blankKeepsAll() {
        var s = OverlaySelection()
        s.query = "  "
        #expect(s.filter(names) { [$0] } == names)
    }

    @Test("The query matches any field, ignoring case and surrounding spaces")
    func matchesAnyField() {
        var s = OverlaySelection()
        s.query = " FE "
        #expect(s.filter(names) { [$0, "path"] } == ["feature/x"])
        s.query = "PATH"
        #expect(s.filter(names) { [$0, "path"] } == names)
    }

    @Test("Moving wraps in both directions and ignores an empty list")
    func moveWraps() {
        var s = OverlaySelection()
        s.move(-1, count: 3)
        #expect(s.selected == 2)
        s.move(1, count: 3)
        #expect(s.selected == 0)
        s.move(1, count: 0)
        #expect(s.selected == 0)
    }
}
