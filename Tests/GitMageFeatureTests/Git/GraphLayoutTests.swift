import XCTest

@testable import GitMageFeature

final class GraphLayoutTests: XCTestCase {
    func testEveryLaneNodeAndEdgeFitsInsideTheGutter() {
        for lanes in [1, 2, 12, 13, 14, 30] {
            let width = GraphLayout.gutterWidth(laneCount: lanes)
            for lane in 0..<lanes {
                // Selected node radius is 5 (the halo is decoration).
                let x = GraphLayout.laneX(lane)
                XCTAssertGreaterThanOrEqual(x - 5, 0, "lane \(lane)/\(lanes) clipped left")
                XCTAssertLessThanOrEqual(x + 5, width, "lane \(lane)/\(lanes) runs under the text")
            }
        }
    }

    func testGutterWidthGrowsWithLaneCountAndUsesFourteenPoints() {
        XCTAssertEqual(GraphLayout.laneSpacing, 14)
        XCTAssertEqual(GraphLayout.gutterWidth(laneCount: 14) - GraphLayout.gutterWidth(laneCount: 13), 14)
        XCTAssertEqual(GraphLayout.gutterWidth(laneCount: 0), GraphLayout.gutterWidth(laneCount: 1))
    }
}
