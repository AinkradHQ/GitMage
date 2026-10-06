import AinkradAppKit
import SwiftUI

/// A neon capsule toggle in place of the stock macOS switch: the track
/// lights with the accent when on, the knob carries a soft glow. Shared
/// across the Settings sections. Retyped to take `HostThemeTokens`.
struct NeonToggle: View {
    @Binding var isOn: Bool
    let tokens: HostThemeTokens

    var body: some View {
        // Kit toggle: chamfered track + luminous thumb; on-tint is the kit's
        // accentPrimary, matching the previous NeonToggle on-state. `tokens` is
        // retained on the API so call sites stay untouched.
        AinkradToggle(isOn: $isOn)
    }
}
