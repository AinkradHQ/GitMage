import Foundation

// MARK: - evasion cases
//
// File-scope (not nested in the suite) because `@Test(arguments:)` reads the
// table from outside the actor, and the suite is `@MainActor`.

/// One spelling of an approving review event. Built by a closure so the table
/// can hold heterogeneous JSON values and still be `Sendable`.
struct PREvasion: Sendable, CustomStringConvertible {
    let label: String
    let value: @Sendable () -> Any
    init(_ label: String, _ value: @escaping @Sendable () -> Any) {
        self.label = label
        self.value = value
    }
    var description: String { label }
}

/// Spellings a caller could try in place of the plain `event: "approve"` that
/// `pr_review`'s guard rejects.
///
/// Unlike `reset`'s `mode`, the sink here is LOOSE — `PrOpActionHandler`
/// lowercases and aliases `"approved"` — so the casing variants are NOT saved
/// by a strict sink the way `"Hard"` is. They have to be caught by the guard
/// itself, which is why it resolves through the sink's own parser.
let approveEvasions: [PREvasion] = [
    PREvasion("plain") { "approve" },
    PREvasion("capitalised") { "Approve" },
    PREvasion("upper-cased") { "APPROVE" },
    PREvasion("mixed case") { "aPpRoVe" },
    PREvasion("the past-tense alias") { "approved" },
    PREvasion("the capitalised alias") { "Approved" },
    PREvasion("the GitHub wire value") { "APPROVED" },
    PREvasion("leading space") { " approve" },
    PREvasion("trailing space") { "approve " },
    PREvasion("array wrapping the string") { ["approve"] },
    PREvasion("object wrapping the string") { ["event": "approve"] },
]
