import XCTest
import Foundation
import SwiftUI
import AinkradAppKit
@testable import GitMageFeature

// MARK: - Minimal HostServices double

@MainActor
final class RecordingContextRegistry: PluginContextRegistry {
    private(set) var sources: [PluginContextToken: @MainActor () -> AgentContextSnapshot?] = [:]
    func register(_ source: @escaping @MainActor () -> AgentContextSnapshot?) -> PluginContextToken {
        let token = PluginContextToken()
        sources[token] = source
        return token
    }
    func remove(_ token: PluginContextToken) { sources[token] = nil }
    func snapshots() -> [AgentContextSnapshot] { sources.values.compactMap { $0() } }
}

private final class FakeDocs: PluginDocumentStore {
    func data(forKey key: String) -> Data? { nil }
    func setData(_ data: Data?, forKey key: String) {}
}
private final class FakeSecrets: PluginSecretStore {
    func secret(forKey key: String) -> String? { nil }
    func setSecret(_ value: String?, forKey key: String) {}
}
private final class FakeLogger: PluginLogger {
    func info(_ message: String) {}
    func error(_ message: String) {}
}
@MainActor private final class FakeAppLauncher: PluginAppLauncher {
    func open(appID: String, payload: String?) {}
    func takePendingLaunch() -> String? { nil }
}
@MainActor private final class FakePresentation: PluginPresentationControl {
    var current: PluginPresentation = .pane
    func set(_ presentation: PluginPresentation) { current = presentation }
    func reset() { current = .pane }
}
private func testTokens() -> HostThemeTokens {
    HostThemeTokens(themeID: "test", background: .black, surface: .black, surfaceElevated: .black,
                    accentPrimary: .black, accentSecondary: .black, accentTertiary: .black, foreground: .black)
}

@MainActor
final class RecordingActionRegistry: AgentActionProvider {
    private(set) var handlers: [AgentActionToken: (String) async -> AgentActionResult] = [:]
    private(set) var ids: [AgentActionToken: String] = [:]
    func register(actionID: String,
                  handler: @escaping @MainActor (String) async -> AgentActionResult) -> AgentActionToken {
        let token = AgentActionToken(); handlers[token] = handler; ids[token] = actionID; return token
    }
    func remove(_ token: AgentActionToken) { handlers[token] = nil; ids[token] = nil }
    func invoke(actionID: String, input: String) async -> AgentActionResult? {
        guard let token = ids.first(where: { $0.value == actionID })?.key,
              let handler = handlers[token] else { return nil }
        return await handler(input)
    }
}

@MainActor
final class FakeHostServices: HostServices {
    // Retain every instance so its ObjectIdentifier stays unique across the
    // never-cleared GitMageRuntime maps (a reused address could otherwise
    // collide with a stale bridge entry from a prior test).
    static var liveInstances: [FakeHostServices] = []

    let documents: PluginDocumentStore = FakeDocs()
    let secrets: PluginSecretStore = FakeSecrets()
    let theme: HostTheme = HostTheme(testTokens())
    let log: PluginLogger = FakeLogger()
    let apps: PluginAppLauncher = FakeAppLauncher()
    let presentation: PluginPresentationControl = FakePresentation()
    let context: PluginContextRegistry
    let actions: AgentActionProvider
    /// Generation 9 added `HostServices.signals`. Plugins CONSUME HostServices
    /// and never implement it in production — this fake is the exception, and
    /// it is the documented cost of adding a protocol requirement: a compiled
    /// bundle keeps loading, but a plugin's test double needs the new member.
    /// `NoopSignalEmitter` is what the SDK ships for exactly this.
    let signals: PluginSignalEmitter = NoopSignalEmitter()
    init(context: PluginContextRegistry, actions: AgentActionProvider = RecordingActionRegistry()) {
        self.context = context
        self.actions = actions
        FakeHostServices.liveInstances.append(self)
    }
}

// A tiny GitContextSource so we can drive the registered closure.
@MainActor
private final class FakeSource: GitContextSource {
    var repo: GitRepositorySnapshot?
    var name: String?
    init(repo: GitRepositorySnapshot?, name: String?) { self.repo = repo; self.name = name }
    func agentRepositorySnapshot() -> GitRepositorySnapshot? { repo }
    func agentRepositoryName() -> String? { name }
}

@MainActor
final class GitMageContextRegistrationTests: XCTestCase {
    func testSameHostSameBridge() {
        let host = FakeHostServices(context: RecordingContextRegistry())
        XCTAssertTrue(GitMageRuntime.contextBridge(for: host) === GitMageRuntime.contextBridge(for: host))
    }

    func testRegistersExactlyOnce() {
        let registry = RecordingContextRegistry()
        let host = FakeHostServices(context: registry)
        _ = GitMageRuntime.contextBridge(for: host)
        _ = GitMageRuntime.contextBridge(for: host)
        XCTAssertEqual(registry.sources.count, 1)
    }

    func testRegisteredSourceReflectsBridge() {
        let registry = RecordingContextRegistry()
        let host = FakeHostServices(context: registry)
        let bridge = GitMageRuntime.contextBridge(for: host)

        XCTAssertTrue(registry.snapshots().isEmpty)   // no active source yet → nil
        let source = FakeSource(
            repo: GitRepositorySnapshot(rootPath: "/r", branchName: "main", upstream: nil,
                                        aheadCount: 0, behindCount: 0, lastCommitSummary: "c", changes: []),
            name: "r")
        bridge.setActiveSource(source)
        let snaps = registry.snapshots()
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps.first?.kind, "git")
        XCTAssertEqual(snaps.first?.title, "Git — r")
    }

    func testDifferentHostsDifferentBridges() {
        let r1 = RecordingContextRegistry(); let h1 = FakeHostServices(context: r1)
        let r2 = RecordingContextRegistry(); let h2 = FakeHostServices(context: r2)
        XCTAssertFalse(GitMageRuntime.contextBridge(for: h1) === GitMageRuntime.contextBridge(for: h2))
        XCTAssertEqual(r1.sources.count, 1)
        XCTAssertEqual(r2.sources.count, 1)
    }
}
