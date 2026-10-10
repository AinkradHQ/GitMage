import AinkradAppKit
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AinkradAppKitUI
@testable import GitMageFeature

/// Glass Native E5: Git Mage's own chrome under Neon and Liquid Glass, written
/// as `<dir>/<name>-neon.png` / `-glass.png`. A tool, not a check: it runs only
/// with AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR (the catalog's `themes/`) set.
/// Captures go through `.build/capture-broker.sh` (the test host has no Screen
/// Recording grant): live windows, because off-screen rendering cannot draw
/// Liquid Glass.
@Suite("Git Mage glass sweep")
@MainActor
struct GlassSweepTests {
    @Test("shoot Git Mage's chrome under Neon and Glass")
    func shoot() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["AINKRAD_SWEEP_DIR"], let themes = env["AINKRAD_THEMES_DIR"] else {
            print("SKIPPED: set AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR — no Git Mage glass sweep")
            return
        }
        let glass = try Self.glassSkin(themes: URL(fileURLWithPath: themes))
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        let model = GitMageViewModel(host: FakeHostServices(context: RecordingContextRegistry()))
        model.repos = [
            GitMageRepoConfig(id: "/tmp/ainkrad", path: "/tmp/ainkrad", name: "Ainkrad", draftCommitMessage: "", lastBranch: ""),
            GitMageRepoConfig(id: "/tmp/lore", path: "/tmp/lore", name: "Lore", draftCommitMessage: "", lastBranch: ""),
        ]
        model.activeRepoID = "/tmp/ainkrad"
        model.branches = [
            GitBranchSummary(name: "development", upstream: "origin/development", isCurrent: true, tracking: nil),
            GitBranchSummary(name: "feat/glass-native", upstream: nil, isCurrent: false, tracking: "ahead 2"),
        ]
        model.commits = [
            GitCommitSummary(id: "a1", shortSHA: "a1b2c3d", summary: "feat(home): the lit brand mark", author: "Ahmed", relativeDate: "2h"),
            GitCommitSummary(id: "b2", shortSHA: "b2c3d4e", summary: "fix(glass): rigid motion", author: "Ahmed", relativeDate: "1h"),
        ]
        model.selectedCommitID = "a1"

        let change = GitChange(
            id: "c", path: "Sources/App.swift", filePath: "Sources/App.swift", sourcePath: nil, statusCode: "M ",
            kind: .modified)
        let files = [DiffFile(id: "f", filename: "Sources/App.swift", status: "modified", patch: "@@ -1 +1 @@\n-a\n+b")]

        let shots: [(String, CGSize, () -> AnyView)] = [
            ("chips", CGSize(width: 520, height: 80), {
                AnyView(HStack {
                    TopBarChip(icon: "folder.fill", label: "Ainkrad", tokens: Self.tokens, action: {})
                    TopBarChip(icon: "arrow.triangle.branch", label: "development", tokens: Self.tokens, action: {})
                })
            }),
            ("repos", CGSize(width: 640, height: 360), { AnyView(RepoManagerPanel(model: model, tokens: Self.tokens, dismiss: {})) }),
            ("branches", CGSize(width: 520, height: 300), { AnyView(BranchManagerPanel(model: model, tokens: Self.tokens, dismiss: {})) }),
            ("history", CGSize(width: 420, height: 260), { AnyView(HistoryContextPane(model: model, tokens: Self.tokens)) }),
            ("changeRow", CGSize(width: 420, height: 60), {
                AnyView(ChangeRow(change: change, isSelected: true, staged: false, tokens: Self.tokens,
                    onSelect: {}, onStage: {}, onUnstage: {}, onDiscard: {}))
            }),
            ("commitBox", CGSize(width: 420, height: 220), {
                AnyView(CommitBox(model: model, tokens: Self.tokens, accent: Self.tokens.accentPrimary, stagedCount: 1))
            }),
            ("diffList", CGSize(width: 520, height: 200), {
                AnyView(FileDiffList(files: files, tokens: Self.tokens, fontSize: 12))
            }),
            ("discussion", CGSize(width: 520, height: 200), {
                AnyView(DiscussionCard(author: "ahmed", timestamp: "2026-10-10T10:00:00Z", text: "Looks **good**.",
                    isPrimary: true, tokens: Self.tokens))
            }),
        ]
        for (name, size, make) in shots {
            for (theme, skin) in [("neon", AinkradSkin.standard), ("glass", glass)] {
                let tokens = HostThemeTokens(skin: skin)
                Self.tokens = tokens
                let view = make()
                    .padding(12)
                    .frame(width: size.width, height: size.height)
                    .background(skin.color(skin.palette.background))
                    .environment(\.ainkradTheme, tokens)
                    .ainkradSkin(skin)
                    .environment(\.colorScheme, .dark)
                try Self.capture(view, size: size, to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(theme).png"))
            }
        }
    }

    /// The tokens of the skin being shot (set per run before each view is built).
    static var tokens = HostThemeTokens(skin: .standard)

    /// `glass-dark.theme` on the standard skin, coloured by `glass-dark.scheme`.
    static func glassSkin(themes: URL) throws -> AinkradSkin {
        let dir = themes.appendingPathComponent("glass")
        let base = try JSONEncoder().encode(AinkradSkin.standard)
        let theme = try Data(contentsOf: dir.appendingPathComponent("glass-dark.theme"))
        let variant = try #require(ainkradLoadThemes([base, theme]).themes["glass.dark"])
        var scheme = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("glass-dark.scheme")))
                as? [String: Any])
        scheme.removeValue(forKey: "appearance")
        scheme.removeValue(forKey: "host")
        scheme["base"] = "glass.dark"
        return try AinkradThemeFile(decoding: JSONSerialization.data(withJSONObject: scheme), bases: ["glass.dark": variant]).skin
    }

    private final class KeyAppearancePanel: NSPanel {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        override var canBecomeKey: Bool { false }
        @objc var hasKeyAppearance: Bool { true }
        @objc var hasMainAppearance: Bool { true }
        @objc var _hasActiveAppearance: Bool { true }
        @objc var _hasActiveAppearanceIgnoringKeyFocus: Bool { true }
    }

    /// A desktop-level window (behind everything, no focus) captured by the broker.
    static func capture(_ view: some View, size: CGSize, to url: URL) throws {
        let panel = KeyAppearancePanel(
            contentRect: NSRect(origin: CGPoint(x: 200, y: 200), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        panel.contentView = NSHostingView(
            rootView: view.environment(\.ainkradMotionBudget, .frozen).environment(\.controlActiveState, .key))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let requests = url.deletingLastPathComponent().appendingPathComponent(".requests", isDirectory: true)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try "\(panel.windowNumber) \(url.path)".write(
            to: requests.appendingPathComponent(UUID().uuidString + ".req"), atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        #expect(FileManager.default.fileExists(atPath: url.path), "no capture broker answered for \(url.lastPathComponent)")
    }
}
