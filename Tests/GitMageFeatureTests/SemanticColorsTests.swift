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
        XCTAssertEqual(GMColor.status(.warning, tokens), tokens.accentTertiary)
    }

    func testDiffColorsAreDistinctFromEachOther() {
        let tokens = makeTokens()
        XCTAssertNotEqual(GMColor.diffAdd(tokens), GMColor.diffRemove(tokens))
    }
}
