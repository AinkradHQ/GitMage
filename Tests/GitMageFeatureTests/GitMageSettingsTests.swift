import XCTest
import SwiftUI
import AinkradAppKit
@testable import GitMageFeature

@MainActor
final class GitMageSettingsTests: XCTestCase {
    func testStoreRoundTripsAndPersists() {
        let documents = MemoryDocumentStore()
        let store = GitMageSettingsStore(documents: documents)
        store.update { $0.backgroundOpacity = 0.5; $0.followThemeAccent = false }

        let reloaded = GitMageSettingsStore(documents: documents)
        XCTAssertEqual(reloaded.settings.backgroundOpacity, 0.5)
        XCTAssertFalse(reloaded.settings.followThemeAccent)
    }

    func testDefensiveDecodeOfPartialPayload() throws {
        let documents = MemoryDocumentStore()
        let partial = "{\"backgroundOpacity\":0.7}".data(using: .utf8)!
        documents.setData(partial, forKey: GitMageSettings.documentID)

        let store = GitMageSettingsStore(documents: documents)
        XCTAssertEqual(store.settings.backgroundOpacity, 0.7)
        XCTAssertTrue(store.settings.followThemeAccent)   // default preserved
        XCTAssertEqual(store.settings.diffFontSize, 12)
    }

    func testResolverClampsOpacityAndPicksAccent() {
        let tokens = HostThemeTokens(
            themeID: "t", background: .black, surface: .gray, surfaceElevated: .gray,
            accentPrimary: .blue, accentSecondary: .purple, accentTertiary: .pink, foreground: .white
        )
        let low = GitMageAppearanceResolver.resolve(settings: GitMageSettings(backgroundOpacity: 0.0), tokens: tokens)
        XCTAssertEqual(low.backgroundOpacity, 0.2)
        let high = GitMageAppearanceResolver.resolve(settings: GitMageSettings(backgroundOpacity: 2.0), tokens: tokens)
        XCTAssertEqual(high.backgroundOpacity, 1.0)
        let themed = GitMageAppearanceResolver.resolve(settings: GitMageSettings(followThemeAccent: true), tokens: tokens)
        XCTAssertEqual(themed.accent, Color.blue)
        let custom = GitMageAppearanceResolver.resolve(settings: GitMageSettings(followThemeAccent: false), tokens: tokens)
        XCTAssertEqual(custom.accent, Color.purple)
    }

    func testCorruptSettingsAreSetAsideNotOverwritten() {
        let seed = Data("{not json".utf8)
        let documents = MemoryDocumentStore()
        documents.setData(seed, forKey: GitMageSettings.documentID)
        let store = GitMageSettingsStore(documents: documents)
        store.update { $0.backgroundOpacity = 0.5 }

        let backups = documents.keys.filter { $0.hasPrefix("\(GitMageSettings.documentID).corrupt-") }
        XCTAssertEqual(backups.count, 1, "corrupt bytes were not set aside")
        XCTAssertEqual(documents.data(forKey: backups.first ?? ""), seed, "backup does not hold the seed bytes")
    }

    func testUnverifiableSettingsSetAsideKeepsOriginalAndStopsSaving() {
        let seed = Data("{not json".utf8)
        let documents = RejectingCorruptDocs()
        documents.setData(seed, forKey: GitMageSettings.documentID)
        let store = GitMageSettingsStore(documents: documents)
        store.update { $0.backgroundOpacity = 0.5 }

        XCTAssertEqual(
            documents.data(forKey: GitMageSettings.documentID), seed,
            "the only copy of the user's data was overwritten")
    }
}

final class MemoryDocumentStore: PluginDocumentStore {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) { storage[key] = data }
    var keys: [String] { Array(storage.keys) }
}

/// An in-memory `PluginDocumentStore` whose `setData` ignores backup keys,
/// simulating a failed verification read-back after the set-aside write.
final class RejectingCorruptDocs: PluginDocumentStore {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) {
        if key.contains(".corrupt-") { return }
        storage[key] = data
    }
    var keys: [String] { Array(storage.keys) }
}
