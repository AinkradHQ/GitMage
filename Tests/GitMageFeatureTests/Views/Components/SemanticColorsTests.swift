import AinkradAppKit
import SwiftUI
import XCTest

@testable import GitMageFeature

final class SemanticColorsTests: XCTestCase {
    private func makeTokens() -> HostThemeTokens {
        HostThemeTokens(
            themeID: "t", background: .black, surface: .gray, surfaceElevated: .gray,
            accentPrimary: .blue, accentSecondary: .purple, accentTertiary: .pink, foreground: .white
        )
    }

    func testStatusMapsToTokens() {
        let tokens = makeTokens()
        XCTAssertEqual(GMColor.status(.open, tokens), tokens.accentPrimary)
        XCTAssertEqual(GMColor.status(.closedMerged, tokens), tokens.accentSecondary)
    }

    func testDiffColorsComeFromTheSkinsSuccessAndDanger() {
        let skin = AinkradSkin.standard
        XCTAssertEqual(GMColor.diffAdd(skin), skin.color(.palette("success", 1)))
        XCTAssertEqual(GMColor.diffRemove(skin), skin.color(.palette("danger", 1)))
        XCTAssertNotEqual(GMColor.diffAdd(skin), GMColor.diffRemove(skin))
    }
}
