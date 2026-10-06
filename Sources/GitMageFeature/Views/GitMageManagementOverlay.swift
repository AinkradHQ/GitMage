import AinkradAppKit
import SwiftUI

/// Which management surface the full-screen overlay is showing.
enum GitMageManagementKind: Identifiable {
    case repos
    case branches
    var id: Int { self == .repos ? 0 : 1 }
}

// MARK: - Overlay host

/// Full-surface, dimmed HUD overlay hosting the repo/branch managers, in the
/// same visual language as the host Launcher & Settings overlays.
struct GitMageManagementOverlay: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let kind: GitMageManagementKind
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                panel
                    .frame(width: min(max(620, geo.size.width * 0.5), 760))
                    .offset(y: -40)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98).combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
    }

    @ViewBuilder private var panel: some View {
        switch kind {
        case .repos:
            RepoManagerPanel(model: model, tokens: tokens, dismiss: dismiss)
        case .branches:
            BranchManagerPanel(model: model, tokens: tokens, dismiss: dismiss)
        }
    }
}

// MARK: - Shared HUD chrome (mirrors host OverlayChrome)

extension View {
    /// Tinted background, rounded clip, top→bottom gradient border, glow +
    /// contact shadow — the same finish as the host's summonable overlays.
    fileprivate func hudPanelChrome(_ tokens: HostThemeTokens) -> some View {
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
private struct GMTargetingBrackets: Shape {
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
private struct OverlaySearchField: View {
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
private struct SectionLabel: View {
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

// MARK: - Repo manager

private struct RepoManagerPanel: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filtered: [GitMageRepoConfig] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.repos }
        return model.repos.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
    }

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            OverlaySearchField(
                placeholder: "Search repositories…",
                text: $query, tokens: tokens, focus: $focused,
                onMove: { move($0, count: results.count) },
                onActivate: { activate(results) },
                onEscape: dismiss
            )
            GlowRule(tokens: tokens)
            SectionLabel(text: "REPOSITORIES · \(model.repos.count)", tokens: tokens)

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, repo in
                            RepoCard(
                                repo: repo,
                                isActive: repo.id == model.activeRepoID,
                                isSelected: index == selected,
                                tokens: tokens,
                                onSelect: {
                                    selected = index
                                    activate(results)
                                },
                                onRemove: { model.removeRepository(repo.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
            }

            GlowRule(tokens: tokens)
            HStack(spacing: 10) {
                AinkradButton(title: "Add Local", style: .primary, icon: "plus") {
                    dismiss()
                    model.addRepositoryFolder()
                }
                AinkradButton(title: "Clone", style: .secondary, icon: "arrow.down.doc") {
                    dismiss()
                    model.startClone()
                }
                Spacer()
                Text("↑↓ navigate   ↩ open   esc close")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .hudPanelChrome(tokens)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: query.isEmpty ? "No repositories yet" : "No matches",
            message: query.isEmpty ? "Add a local folder or clone one to begin." : "Try a different search.",
            tokens: tokens
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func activate(_ results: [GitMageRepoConfig]) {
        guard results.indices.contains(selected) else { return }
        model.selectRepository(results[selected].id)
        dismiss()
    }
}

private struct RepoCard: View {
    let repo: GitMageRepoConfig
    let isActive: Bool
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? tokens.accentPrimary : tokens.foreground.opacity(0.6))
                Spacer()
                if isActive {
                    Text("ACTIVE")
                        .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                        .foregroundStyle(tokens.accentPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
                } else if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 11))
                            .foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                    .buttonStyle(.plain).help("Remove from library")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(AinkradFont.display(14, weight: .semibold))
                    .foregroundStyle(tokens.foreground).lineLimit(1)
                Text(repo.path)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(height: 96, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(
                    isActive
                        ? tokens.accentPrimary.opacity(0.10)
                        : tokens.surfaceElevated.opacity(hovering || isSelected ? 0.7 : 0.4))
        )
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(
                    isActive
                        ? tokens.accentPrimary.opacity(0.55)
                        : tokens.foreground.opacity(hovering ? 0.14 : 0.06),
                    lineWidth: isActive ? 1.2 : 1)
        )
        .overlay(
            GMTargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Branch manager

private struct BranchManagerPanel: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var filtered: [GitBranchSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.branches }
        return model.branches.filter { $0.name.lowercased().contains(q) }
    }

    /// When the search matches nothing, the query becomes a create candidate.
    private var createName: String {
        query.trimmingCharacters(in: .whitespaces)
    }
    private var canCreate: Bool {
        !createName.isEmpty && !model.branches.contains { $0.name == createName }
    }

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            OverlaySearchField(
                placeholder: "Search or name a new branch…",
                text: $query, tokens: tokens, focus: $focused,
                onMove: { move($0, count: results.count) },
                onActivate: { activate(results) },
                onEscape: dismiss
            )
            GlowRule(tokens: tokens)
            SectionLabel(text: "BRANCHES · \(model.branches.count)", tokens: tokens)

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, branch in
                            BranchRow(
                                branch: branch,
                                isSelected: index == selected,
                                tokens: tokens,
                                onCheckout: {
                                    selected = index
                                    activate(results)
                                },
                                onDelete: { model.deleteBranch(branch.name) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
            }

            GlowRule(tokens: tokens)
            HStack(spacing: 10) {
                AinkradButton(
                    title: canCreate ? "Create \"\(createName)\"" : "Create Branch",
                    style: .primary, icon: "arrow.branch"
                ) {
                    create()
                }
                .disabled(!canCreate)
                Spacer()
                Text("↑↓ navigate   ↩ checkout   esc close")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .hudPanelChrome(tokens)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmptyStateView(
                icon: "arrow.triangle.branch",
                title: canCreate ? "No matching branch" : "No branches",
                message: canCreate ? "Press ↩ or Create to make \"\(createName)\"." : "Create your first branch below.",
                tokens: tokens
            )
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    /// Return key: if the query matches branches, checkout the selected one;
    /// otherwise treat the query as a new branch name.
    private func activate(_ results: [GitBranchSummary]) {
        if results.isEmpty && canCreate {
            create()
            return
        }
        guard results.indices.contains(selected) else { return }
        let branch = results[selected]
        guard !branch.isCurrent else { return }
        model.selectedBranchName = branch.name
        model.checkoutSelectedBranch()
        dismiss()
    }

    private func create() {
        guard canCreate else { return }
        model.newBranchName = createName
        model.createBranch()
        dismiss()
    }
}

private struct BranchRow: View {
    let branch: GitBranchSummary
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onCheckout: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(branch.isCurrent ? tokens.accentPrimary : tokens.foreground.opacity(0.25))
                    .frame(width: 8, height: 8)
                if branch.isCurrent {
                    Circle().stroke(tokens.accentPrimary.opacity(0.4), lineWidth: 4).frame(width: 8, height: 8)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(AinkradFont.display(13, weight: branch.isCurrent ? .semibold : .regular))
                    .foregroundStyle(tokens.foreground.opacity(branch.isCurrent ? 1 : 0.9))
                Text(branch.subtitle)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.42)).lineLimit(1)
            }
            Spacer(minLength: 6)

            if branch.isCurrent {
                Text("CURRENT")
                    .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                    .foregroundStyle(tokens.accentPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
            } else if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                .buttonStyle(.plain).help("Delete branch")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(
            ChamferShape(cut: AinkradRadius.sm)
                .fill(
                    branch.isCurrent
                        ? tokens.accentPrimary.opacity(0.09)
                        : ((hovering || isSelected) ? tokens.accentPrimary.opacity(0.10) : .clear))
        )
        .overlay(
            GMTargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(1)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !branch.isCurrent { onCheckout() } }
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}
