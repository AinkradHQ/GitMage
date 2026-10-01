import Observation
import Foundation
import AinkradAppKit

/// Observable owner of `GitMageSettings`, backed by app-scoped `documents`.
/// Editing persists immediately and publishes to observers so the settings UI,
/// every view, and `chromeFill` restyle live.
@MainActor
@Observable
final class GitMageSettingsStore {
    private(set) var settings: GitMageSettings
    private let documents: PluginDocumentStore
    private var canSave = true
    private static let key = GitMageSettings.documentID

    init(documents: PluginDocumentStore) {
        self.documents = documents
        let loaded = loadDocument(
            GitMageSettings.self, key: Self.key, from: documents, app: "gitmage")
        self.settings = loaded.value ?? GitMageSettings()
        self.canSave = loaded.canSave
        applyTypography()
    }

    func update(_ mutate: (inout GitMageSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
        applyTypography()
        guard canSave else {
            AinkradLog.logger(app: "gitmage", area: "persistence")
                .error("saving is off: the loaded document did not decode and could not be set aside")
            return
        }
        if let data = try? JSONEncoder().encode(updated) {
            documents.setData(data, forKey: Self.key)
        }
    }

    /// Pushes the current typography settings into `AinkradFont` so every
    /// `display`/`mono` call across the UI reflects them.
    private func applyTypography() {
        AinkradFont.config = AinkradFont.Config(
            scale: CGFloat(settings.textScale),
            displayFamily: settings.displayFontName,
            monoFamily: settings.monoFontName
        )
    }
}
