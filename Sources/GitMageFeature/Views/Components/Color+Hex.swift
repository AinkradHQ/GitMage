import SwiftUI

extension Color {
    /// Parses a 6-digit hex string (as returned by the GitHub labels API,
    /// no leading `#`) into a `Color`; nil if unparseable, so the caller
    /// falls back to a theme token.
    init?(hex: String) {
        var hexValue: UInt64 = 0
        let scanner = Scanner(string: hex)
        guard scanner.scanHexInt64(&hexValue), hex.count == 6 else { return nil }
        let r = Double((hexValue >> 16) & 0xFF) / 255
        let g = Double((hexValue >> 8) & 0xFF) / 255
        let b = Double(hexValue & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)  // design-lint: allow raw-color GitHub label data
    }
}
