import Foundation

/// #86 — **deferring is waiting.** There is no separate "deferred" category any more: an item
/// put off until a day is a waiting item with that day as its follow-up date and **no who**.
///
/// - A who-less waiting item sits in Waiting until its follow-up date; on that day it **returns
///   to Next by itself** (`Rules.isBackInNext`), holds a Next slot again and shows the `back`
///   badge — the behaviour a `defer` date had. Its file keeps `status: waiting` until the user
///   changes the item.
/// - A waiting item **with** a who stays in Waiting and turns into a `chase` item, as before (W2).
///
/// A `defer:` line is legacy. `GTDMarkdown` reads it tolerantly through
/// `foldingDeferIntoWaiting()` (like `backlog`/`maybe` for `someday`, R-1) and rewrites it as
/// `status: waiting` + `followUpDate:` only when the user changes that note; the reducer folds
/// any `deferDate` a command still sets (the inbox card's defer chip, "defer" in Next) the same
/// way, so no open action ever leaves the reducer carrying one.
extension Action {

    /// A waiting item without a who — the shape a deferral takes (#86). Blank counts as none.
    public var isWhoLessWaiting: Bool {
        guard status == .waiting else { return false }
        return (waitingFor ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The same action with a legacy `defer` date folded into the waiting fields (#86).
    ///
    /// Closed actions and actions without a `defer` date are returned unchanged. A waiting
    /// action keeps its who and follow-up date (the defer date fills in only a missing
    /// follow-up date); any other open status becomes who-less `waiting` following up on the
    /// defer date — including a defer date already in the past, which reads as an item that is
    /// back in Next, exactly where the old defer date had put it.
    public func foldingDeferIntoWaiting() -> Action {
        guard let deferDate, !status.isClosed else { return self }
        var folded = self
        folded.deferDate = nil
        if status == .waiting {
            if folded.followUpDate == nil { folded.followUpDate = deferDate }
        } else {
            folded.status = .waiting
            folded.waitingFor = nil
            folded.followUpDate = deferDate
        }
        return folded
    }
}

extension Rules {

    /// #86 — a who-less waiting item whose follow-up date has arrived is back in Next: it is
    /// listed there, holds a cap slot, and leaves the Waiting list. Items with a who never
    /// return by themselves; they become `chase` items (W2).
    public static func isBackInNext(_ action: Action, today: Day) -> Bool {
        guard action.isWhoLessWaiting, let followUp = action.followUpDate else { return false }
        return followUp <= today
    }

    /// The status an action behaves as **today**: `next` for a who-less waiting item that is
    /// back (#86), its own status otherwise. The reducer judges transitions out of such an item
    /// as transitions out of Next, so starting or re-filing it asks for nothing new.
    public static func effectiveStatus(_ action: Action, today: Day) -> ActionStatus {
        isBackInNext(action, today: today) ? .next : action.status
    }
}
