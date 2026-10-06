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
            errorMessage = error.displayMessage
        }
    }

    /// A secondary load: on failure it is logged, shown in the banner (unless
    /// `showFailure` is false, for a failure that is routine) and the caller
    /// gets `fallback`, so an empty list is never a hidden error.
    func optionalLoad<T>(
        _ what: String, fallback: T, showFailure: Bool = true, _ load: () async throws -> T
    ) async -> T {
        do {
            return try await load()
        } catch {
            if Task.isCancelled { return fallback }
            Log.forge.error("Failed to load \(what): \(error.displayMessage)")
            if showFailure {
                if let forgeError = error as? ForgeError {
                    handleForgeError(forgeError)
                } else {
                    errorMessage = error.displayMessage
                }
            }
            return fallback
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
