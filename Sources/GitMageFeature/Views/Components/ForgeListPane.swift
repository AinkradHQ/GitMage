import AinkradAppKit
import SwiftUI

// The pieces the Pull Requests and Issues context panes share: the gate in
// front of them, the filter toolbar and the paged list.

/// What stands between the pane and its list: a GitHub remote, then a token.
enum ForgeGate {
    case needsGitHubRemote
    case needsToken
    case invalidToken(String)
    case ready

    init(hasGitHubRemote: Bool, authState: ForgeAuthState) {
        guard hasGitHubRemote else {
            self = .needsGitHubRemote
            return
        }
        switch authState {
        case .missingToken: self = .needsToken
        case .invalid(let message): self = .invalidToken(message)
        case .unknown, .valid: self = .ready
        }
    }

    /// The message for a closed gate, `nil` when the list may show.
    func message(area: String) -> String? {
        switch self {
        case .needsGitHubRemote: return "\(area) need a GitHub `origin` remote."
        case .needsToken: return "Add a GitHub token in Settings."
        case .invalidToken(let message): return message
        case .ready: return nil
        }
    }
}

/// A full-pane empty state, used for closed gates and load errors.
struct ForgeMessage: View {
    let icon: String
    let title: String
    let message: String
    let tokens: HostThemeTokens

    var body: some View {
        AinkradEmptyState(icon: icon, title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header, Open/Closed picker, search and label chips.
struct ForgeFilterToolbar<Filter: Hashable, Trailing: View>: View {
    let title: String
    let loaded: Int
    let total: Int
    let tokens: HostThemeTokens
    let filters: [Filter]
    @Binding var filter: Filter
    let filterLabel: (Filter) -> String
    @Binding var searchText: String
    let searchPlaceholder: String
    let labels: [IssueLabel]
    let selectedLabels: Set<String>
    let toggleLabel: (String) -> Void
    let load: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(spacing: skin.spacing.sm) {
            PaneHeader(
                title: title, count: loaded, countText: total > 0 ? "\(loaded) / \(total)" : "\(loaded)",
                tokens: tokens, trailing: trailing)
            AinkradSegmentedPicker(
                items: filters,
                selection: Binding(
                    get: { filter },
                    set: { newValue in
                        if filter != newValue {
                            filter = newValue
                            load()
                        }
                    }
                ),
                label: filterLabel
            )
            .padding(.horizontal, skin.spacing.md)
            AinkradSearchField(text: $searchText, placeholder: searchPlaceholder, onSubmit: load)
                .padding(.horizontal, skin.spacing.md)
            if !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: skin.size.s6) {
                        ForEach(labels) { label in
                            AinkradSwatchChip(
                                label: label.name,
                                swatch: Color(hex: label.color) ?? skin.color(skin.text.muted),  // design-lint: allow hex-color GitHub label data
                                isOn: selectedLabels.contains(label.name),
                                onTap: { toggleLabel(label.name) }
                            )
                        }
                    }
                }
                .padding(.horizontal, skin.spacing.md)
            }
        }
        .padding(.bottom, skin.spacing.sm)
    }
}

extension ForgeFilterToolbar where Trailing == EmptyView {
    init(
        title: String, loaded: Int, total: Int, tokens: HostThemeTokens, filters: [Filter],
        filter: Binding<Filter>, filterLabel: @escaping (Filter) -> String, searchText: Binding<String>,
        searchPlaceholder: String, labels: [IssueLabel], selectedLabels: Set<String>,
        toggleLabel: @escaping (String) -> Void, load: @escaping () -> Void
    ) {
        self.init(
            title: title, loaded: loaded, total: total, tokens: tokens, filters: filters, filter: filter,
            filterLabel: filterLabel, searchText: searchText, searchPlaceholder: searchPlaceholder,
            labels: labels, selectedLabels: selectedLabels, toggleLabel: toggleLabel, load: load,
            trailing: { EmptyView() })
    }
}

/// Spinner, error, empty state, or the paged rows (loading more when the last one appears).
struct ForgeItemList<Item: Identifiable, Row: View>: View {
    @Environment(\.ainkradSkin) private var skin
    let items: [Item]
    let isLoading: Bool
    let isLoadingMore: Bool
    let errorMessage: String?
    let icon: String
    let areaTitle: String
    let emptyTitle: String
    let tokens: HostThemeTokens
    let loadMore: () -> Void
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        if isLoading {
            AinkradLoadingState()
        } else if let errorMessage {
            ForgeMessage(icon: icon, title: areaTitle, message: errorMessage, tokens: tokens)
        } else if items.isEmpty {
            ForgeMessage(icon: icon, title: emptyTitle, message: "Nothing matches this filter.", tokens: tokens)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item)
                            .onAppear { if index == items.count - 1 { loadMore() } }
                    }
                    if isLoadingMore { AinkradLoadingState() }
                }
                .padding(.horizontal, skin.spacing.md).padding(.bottom, skin.spacing.md)
            }
        }
    }
}
