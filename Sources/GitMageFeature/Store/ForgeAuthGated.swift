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
        // SAFETY: the provider is immutable and only used here, on the main actor;
        // the same exemption the view models' stored `provider` already carries.
        nonisolated(unsafe) let forge = provider
        do {
            _ = try await forge.verify()
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
        errorMessage = error.errorDescription
        if error == .unauthorized {
            authState = .invalid(error.errorDescription ?? "Invalid token.")
        }
    }
}
