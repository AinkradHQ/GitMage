import SwiftUI

extension Color {
    /// Parses a 6-digit hex string (as returned by the GitHub labels API,
    /// no leading `#`) into a `Color`. Falls back to gray if unparseable.
    init(hex: String) {
        var hexValue: UInt64 = 0
        let scanner = Scanner(string: hex)
        guard scanner.scanHexInt64(&hexValue), hex.count == 6 else {
            self = .gray
            return
        }
        let r = Double((hexValue & 0xFF0000) >> 16) / 255
        let g = Double((hexValue & 0x00FF00) >> 8) / 255
        let b = Double(hexValue & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
