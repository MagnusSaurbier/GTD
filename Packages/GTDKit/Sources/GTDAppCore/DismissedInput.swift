import Foundation

/// #85 — a one-field sheet (quick capture, a list's `+`) left **without its buttons**: swiped
/// away, `Esc`, a click outside. Written content is never lost, so such a sheet still sends
/// what was typed, as if its main button had been pressed. Only the explicit `Cancel` button
/// discards — that is a decision, not an accident.
public enum DismissedInput {
    /// True when the sheet should send `text` as it goes away: something was typed, and neither
    /// `Cancel` nor the main button has already settled it.
    public static func keeps(_ text: String, settled: Bool) -> Bool {
        !settled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
