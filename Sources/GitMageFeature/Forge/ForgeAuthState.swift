import Foundation

/// Shared auth-verification state for forge-backed features (Pull Requests,
/// Issues): whether a token is configured and whether the forge accepted it.
enum ForgeAuthState: Equatable {
    case unknown
    case missingToken
    case valid
    case invalid(String)
}
