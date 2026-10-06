import AinkradAppKit
import SwiftUI

// MARK: - Shared HUD chrome (mirrors host OverlayChrome)

extension View {
    /// Tinted background, rounded clip, top→bottom gradient border, glow +
    /// contact shadow — the same finish as the host's summonable overlays.
    func hudPanelChrome(_ tokens: HostThemeTokens) -> some View {
        self
            // Translucent + blurred, matching the host's summonable overlays
            // (was a near-opaque 0.94 fill). VisualEffectBlur is the kit's
            // NSVisualEffectView wrapper.
            .background {
                ZStack {
                    VisualEffectBlur()
                    tokens.background.opacity(0.55)
                }
            }
            .clipShape(ChamferShape(cut: AinkradRadius.panel))
            .overlay(
                ChamferShape(cut: AinkradRadius.panel)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tokens.accentSecondary.opacity(0.55),
                                tokens.accentPrimary.opacity(0.25),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tokens.accentPrimary.opacity(0.35), radius: 42)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

/// The brand chevron mark, drawn locally so the plugin can glow/tint it.
private struct GMChevronMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w * 0.68, y: h))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.42))
        p.addLine(to: CGPoint(x: w * 0.32, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

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

/// The launcher-style command field: glowing chevron + large search field.
struct OverlaySearchField: View {
    let placeholder: String
    @Binding var text: String
    let tokens: HostThemeTokens
    var focus: FocusState<Bool>.Binding
    let onMove: (Int) -> Void
    let onActivate: () -> Void
    let onEscape: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GMChevronMark()
                .fill(tokens.accentSecondary)
                .frame(width: 16, height: 14)
                .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 6)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(17))
                .foregroundStyle(tokens.foreground)
                .tint(tokens.accentSecondary)
                .focused(focus)
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onMove(-1)
                    return .handled
                }
                .onKeyPress(.return) {
                    onActivate()
                    return .handled
                }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
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
