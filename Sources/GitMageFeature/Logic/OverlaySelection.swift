import AinkradAppKit
import Foundation

/// The search text and keyboard-selected row of a management overlay (repos,
/// branches): filter by the trimmed query, wrap the selection on arrow keys.
struct OverlaySelection {
    var query = ""
    var selected = 0

    /// `items` unchanged for a blank query, else those whose `fields` contain it, case-insensitively.
    func filter<T>(_ items: [T], fields: (T) -> [String]) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in fields(item).contains { $0.lowercased().contains(q) } }
    }

    mutating func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    /// The command field's arrow keys: ↑/↓ move and report `true`; ←/→ report
    /// `false` so the caret moves instead.
    mutating func move(_ arrow: AinkradArrow, count: Int) -> Bool {
        switch arrow {
        case .up: move(-1, count: count)
        case .down: move(1, count: count)
        default: return false
        }
        return true
    }
}
