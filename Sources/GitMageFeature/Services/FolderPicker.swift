import AppKit

/// The modal "choose a folder" panel the repo picker and the worktree
/// destination field both open.
enum FolderPicker {
    /// The chosen folder, or `nil` when the user cancels.
    @MainActor
    static func pick(
        title: String? = nil, prompt: String? = nil, message: String? = nil, resolvesUbiquitousConflicts: Bool = true
    ) -> URL? {
        let panel = NSOpenPanel()
        if let title { panel.title = title }
        if let prompt { panel.prompt = prompt }
        if let message { panel.message = message }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.canResolveUbiquitousConflicts = resolvesUbiquitousConflicts
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
