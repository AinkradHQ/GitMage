import SwiftUI
import AinkradAppKit

public struct GitMageApp: AinkradApp {
    public static let id = "gitmage"
    public static let displayName = "Git Mage"
    public static let icon = "wand.and.stars"

    public static func makeRootView(host: HostServices) -> AnyView {
        makeRootView(host: host, mode: .advanced)
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(GitMageSettingsView(
            settingsStore: GitMageRuntime.settingsStore(for: host),
            theme: host.theme,
            host: host
        ))
    }

    /// The window surface: the theme surface at the configured opacity so the
    /// title bar reads continuous with the body, and the host reveals its shared
    /// blurred backdrop when opacity < 1.
    public static func chromeFill(host: HostServices) -> Color? {
        let appearance = GitMageAppearanceResolver.resolve(
            settings: GitMageRuntime.settingsStore(for: host).settings,
            tokens: host.theme.tokens
        )
        return host.theme.tokens.surface.opacity(appearance.backgroundOpacity)
    }
}

/// Publishes Git Mage's git operations to the host assistant as MCP tools.
/// Cached per host by the runtime, so the assistant and the UI share one client.
extension GitMageApp: AinkradAppMCP {
    public static func makeMCPServer(host: HostServices) -> MCPAppServer {
        GitMageRuntime.mcpServer(for: host)
    }
}

/// Generation 8: release this instance when the host closes it.
///
/// `GitMageRuntime` held static, never-evicted registries — settings store,
/// context bridge, MCP server. Closing Git Mage left them all live for the rest
/// of the process, including a context source the agent kept consulting.
///
/// `host` is nil here because teardown is keyed on identity alone; the runtime
/// keeps the tokens it needs to unregister.
extension GitMageApp: AinkradAppTeardown {
    public static func teardown(instance: PluginInstanceID) {
        GitMageRuntime.teardown(instance: instance, host: nil)
    }
}

/// Generation 11: Git Mage's basic mode is repo, branch, Fetch, Pull.
extension GitMageApp: AinkradAppModes {
    public static func makeRootView(host: HostServices, mode: PluginMode) -> AnyView {
        switch mode {
        case .basic:
            return AnyView(GitMageBasicRoot(host: host))
        case .advanced:
            return AnyView(GitMageShell(host: host, settingsStore: GitMageRuntime.settingsStore(for: host)))
        // Resilient enum: fall back to advanced, never to a stripped view for a
        // mode this build does not understand.
        @unknown default:
            return AnyView(GitMageShell(host: host, settingsStore: GitMageRuntime.settingsStore(for: host)))
        }
    }
}

/// Owns the basic view's model, so it lives for the pane rather than being
/// rebuilt on every render — `BlockView` calls `makeRootView` each body pass.
private struct GitMageBasicRoot: View {
    let host: HostServices
    @StateObject private var model: GitMageViewModel

    init(host: HostServices) {
        self.host = host
        _model = StateObject(wrappedValue: GitMageViewModel(host: host))
    }

    var body: some View {
        GitMageBasicView(host: host, model: model)
    }
}
