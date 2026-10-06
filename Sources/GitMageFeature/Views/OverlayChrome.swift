import AinkradAppKit
import SwiftUI

// MARK: - Overlay pieces

/// Four corner brackets — the targeting-cursor treatment for the selected row.
struct GMTargetingBrackets: Shape {
    var length: CGFloat = 8
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return p
    }
}

/// Mono, kerned section label (matches launcher "APPS").
struct SectionLabel: View {
    let text: String
    let tokens: HostThemeTokens
    var body: some View {
        Text(text)
            .font(AinkradFont.mono(9, weight: .medium))
            .kerning(2.5)
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}
