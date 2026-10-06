import AinkradAppKit
import SwiftUI

// MARK: - Chips that open the management overlays

/// Top-bar chip that opens the full-surface repo-management overlay.
struct RepoSwitcher: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    var shortcut: String? = nil
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "folder.badge.gearshape",
            label: model.activeRepo?.name ?? "No Repository",
            tooltip: "Repositories",
            shortcut: shortcut,
            tokens: tokens,
            action: onOpen
        )
    }
}

/// Top-bar chip that opens the full-surface branch-management overlay.
struct BranchChip: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    var shortcut: String? = nil
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "arrow.triangle.branch",
            label: model.snapshot?.branchName ?? "—",
            tooltip: "Branches",
            shortcut: shortcut,
            tokens: tokens,
            action: onOpen
        )
    }
}

// MARK: - Shared HUD chip

/// A gaming-HUD trigger: translucent fill, gradient accent border, accent
/// glow on hover, glowing leading icon and a chevron affordance.
struct TopBarChip: View {
    let icon: String
    let label: String
    var tooltip: String? = nil
    var shortcut: String? = nil
    let tokens: HostThemeTokens
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.accentSecondary)
                    .shadow(color: tokens.accentSecondary.opacity(hovering ? 0.8 : 0.4), radius: hovering ? 5 : 2)
                Text(label)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(hovering ? 0.7 : 0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hudButtonSurface(tokens: tokens, kind: .chip, hovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradTooltip(shortcutTooltip(tooltip ?? label, shortcut))
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}

/// Composes a tooltip: "Fetch  ⌥⌘F" when a shortcut is bound, else just the label.
func shortcutTooltip(_ label: String, _ shortcut: String?) -> String {
    guard let shortcut, !shortcut.isEmpty else { return label }
    return "\(label)  \(shortcut)"
}

// MARK: - Shared HUD surface finish

enum HUDButtonKind { case chip, secondary, primary, destructive }

private struct HUDButtonSurface: ViewModifier {
    let tokens: HostThemeTokens
    let kind: HUDButtonKind
    let hovering: Bool

    // Single choke point: chamfering here cascades to every top-bar chip /
    // repo/branch switcher that finishes with `.hudButtonSurface`.
    private var shape: ChamferShape { ChamferShape(cut: AinkradRadius.sm) }

    // Flat kit chamfer surface — the bespoke gloss gradient, gradient rim, and
    // "powered edge" capsule were removed so the chip reads like `AinkradButton`
    // (chamfer fill + a single accent border + a hover-only accent glow).
    func body(content: Content) -> some View {
        content
            .background(fill.clipShape(shape))
            .overlay(
                shape.strokeBorder(tokens.accentSecondary.opacity(hovering ? 0.6 : 0.3), lineWidth: 1)
            )
            .shadow(color: glowColor, radius: glowRadius, y: hovering ? 3 : 1)
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [
                    tokens.accentPrimary.opacity(hovering ? 1 : 0.92),
                    tokens.accentPrimary.opacity(hovering ? 0.9 : 0.72),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .destructive:
            LinearGradient(
                colors: [
                    tokens.accentTertiary.opacity(hovering ? 0.28 : 0.16),
                    tokens.accentTertiary.opacity(hovering ? 0.18 : 0.10),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary, .chip:
            LinearGradient(
                colors: [
                    tokens.surfaceElevated.opacity(hovering ? 0.85 : 0.5),
                    tokens.surfaceElevated.opacity(hovering ? 0.55 : 0.28),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var glowColor: Color {
        switch kind {
        case .primary: return tokens.accentPrimary.opacity(hovering ? 0.55 : 0.35)
        case .destructive: return tokens.accentTertiary.opacity(hovering ? 0.4 : 0.1)
        case .secondary, .chip: return tokens.accentPrimary.opacity(hovering ? 0.32 : 0.06)
        }
    }

    private var glowRadius: CGFloat {
        switch kind {
        case .primary: return hovering ? 14 : 9
        case .destructive: return hovering ? 12 : 4
        case .secondary, .chip: return hovering ? 11 : 3
        }
    }
}

extension View {
    func hudButtonSurface(tokens: HostThemeTokens, kind: HUDButtonKind, hovering: Bool) -> some View {
        modifier(HUDButtonSurface(tokens: tokens, kind: kind, hovering: hovering))
    }
}

// MARK: - Nav rail item

/// A single icon in the left nav rail, in the gaming-HUD language: a glowing
/// leading "spine" indicator and a bordered accent tile slide to the active
/// area via a shared matched-geometry namespace; hover lifts inactive icons.
struct NavRailItem: View {
    let area: NavArea
    let isActive: Bool
    let tokens: HostThemeTokens
    let namespace: Namespace.ID
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Leading spine — the moving active indicator.
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tokens.accentSecondary)
                            .frame(width: 3, height: 20)
                            .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 5)
                            .matchedGeometryEffect(id: "navSpine", in: namespace)
                    }
                }
                .frame(width: 5)

                ZStack {
                    if isActive {
                        ChamferShape(cut: AinkradRadius.md)
                            .fill(tokens.accentPrimary.opacity(0.16))
                            .overlay(
                                ChamferShape(cut: AinkradRadius.md)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                tokens.accentSecondary.opacity(0.6),
                                                tokens.accentPrimary.opacity(0.25),
                                            ],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: tokens.accentPrimary.opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "navTile", in: namespace)
                    } else if hovering {
                        ChamferShape(cut: AinkradRadius.md)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    }

                    Image(systemName: area.icon)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(
                            isActive
                                ? tokens.accentPrimary
                                : tokens.foreground.opacity(hovering ? 0.9 : 0.6)
                        )
                        .shadow(color: isActive ? tokens.accentPrimary.opacity(0.7) : .clear, radius: 5)
                }
                .frame(width: 40, height: 36)
            }
            .frame(width: 52, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradTooltip(shortcutTooltip(area.title, shortcut))
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Keyboard shortcut dispatch

/// An invisible layer of zero-size buttons, one per bound command, each
/// carrying its `.keyboardShortcut`. Placed in the shell background so the
/// bindings fire window-wide without depending on which control is on screen.
struct ShortcutLayer: View {
    let shortcuts: [String: KeyChord]
    let hasActiveRepo: Bool
    let perform: (GitMageCommand) -> Void

    var body: some View {
        ZStack {
            ForEach(GitMageCommand.allCases) { command in
                if let chord = shortcuts[command.rawValue],
                    chord.hasModifier,
                    let equivalent = chord.keyEquivalent
                {
                    Button(action: { perform(command) }) { Color.clear.frame(width: 0, height: 0) }
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .keyboardShortcut(equivalent, modifiers: chord.eventModifiers)
                        .disabled(command.requiresRepo && !hasActiveRepo)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}
