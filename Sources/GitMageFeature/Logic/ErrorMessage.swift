import Foundation

extension Error {
    /// The text the UI shows for a failure: the error's own description when it
    /// has one, else the system's.
    var displayMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
