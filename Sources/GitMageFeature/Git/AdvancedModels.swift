import Foundation

enum ResetMode: String, CaseIterable {
    case soft
    case mixed
    case hard
}

enum GitOperationState: Equatable {
    case none
    case rebasing
    case cherryPicking
    case reverting

    var isActive: Bool {
        self != .none
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .rebasing: return "Rebasing"
        case .cherryPicking: return "Cherry-picking"
        case .reverting: return "Reverting"
        }
    }
}

struct GitTag: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let message: String?
}
