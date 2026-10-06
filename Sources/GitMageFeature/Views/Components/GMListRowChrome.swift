import AinkradAppKit
import SwiftUI

/// The hover wash, selection fill and glowing spine every list row shares.
/// Local on purpose: GM-6 swaps it for the kit's `AinkradListRow`.
///
/// The row owns `hovering` (its trailing actions fade in with it) and passes the
/// binding in; the tap gestures stay on the row, after this modifier.
struct GMListRowChrome: ViewModifier {
    let tokens: HostThemeTokens
    let isSelected: Bool
    @Binding var hovering: Bool
    /// The selection fill and spine colour.
    var accent: Color?
    /// The spine's height and leading inset. `nil` draws no spine.
    var spine: (height: CGFloat, inset: CGFloat)? = (18, 1)
    /// Vertical inset of the fill, for rows that pad themselves.
    var fillInset: CGFloat = 0
    var animatesSelection = true
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let tint = accent ?? tokens.accentPrimary
        content
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(
                        isSelected
                            ? tint.opacity(0.13)
                            : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear)
                    )
                    .padding(.vertical, fillInset)
            )
            .overlay(alignment: .leading) {
                if let spine {
                    Capsule().fill(tint)
                        .frame(width: 3, height: spine.height)
                        .shadow(color: tint.opacity(0.8), radius: 4)
                        .padding(.leading, spine.inset)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: animatesSelection ? isSelected : false)
    }
}

extension View {
    func gmListRowChrome(
        tokens: HostThemeTokens, isSelected: Bool, hovering: Binding<Bool>, accent: Color? = nil,
        spine: (height: CGFloat, inset: CGFloat)? = (18, 1), fillInset: CGFloat = 0, animatesSelection: Bool = true
    ) -> some View {
        modifier(
            GMListRowChrome(
                tokens: tokens, isSelected: isSelected, hovering: hovering, accent: accent, spine: spine,
                fillInset: fillInset, animatesSelection: animatesSelection))
    }
}
