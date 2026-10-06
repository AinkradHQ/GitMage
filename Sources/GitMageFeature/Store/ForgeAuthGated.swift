import Foundation

/// What the Pull Requests and Issues view models share about the token: how it
/// is verified and how a forge error becomes banner text (and an invalid token).
@MainActor
protocol ForgeAuthGated: AnyObject {
    var authState: ForgeAuthState { get set }
    var errorMessage: String? { get set }
}

extension ForgeAuthGated {
    /// Checks the token against the forge. No token or provider is `.missingToken`; a rejected one `.invalid`.
    func verifyToken(provider: GitForgeProvider?, auth: GitForgeAuth) async {
        guard let token = auth.token(), !token.isEmpty, let provider else {
            authState = .missingToken
            return
        }
        do {
            _ = try await provider.verify()
            authState = .valid
        } catch let error as ForgeError {
            if error == .unauthorized {
                authState = .invalid(error.errorDescription ?? "Invalid token.")
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleForgeError(_ error: ForgeError) {
        if Task.isCancelled { return }  // a superseded load, not a failure to show
        errorMessage = error.errorDescription
        if error == .unauthorized {
            authState = .invalid(error.errorDescription ?? "Invalid token.")
        }
    }
}
