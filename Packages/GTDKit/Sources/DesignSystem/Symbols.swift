import Foundation

/// The canonical, exhaustive SF Symbols map (STYLEGUIDE §7). A concept missing here is added
/// to the style guide **first**, then to this file. Views never write a symbol name.
public enum Symbols {
    public static let inbox = "tray"
    public static let next = "arrow.right.circle"
    /// Someday — the single "not now" tier (STYLEGUIDE §7).
    public static let someday = "moon.zzz"
    public static let waiting = "hourglass"
    public static let chase = "bell.badge"
    public static let projects = "square.stack"
    public static let area = "folder"
    public static let knowledge = "books.vertical"
    public static let trash = "trash"
    public static let capture = "plus.circle"
    /// The leading glyph of an unset "add a value" chip (`Defer`, `Due`, `Project`). The chip's
    /// title never repeats it as a literal "+".
    public static let addValue = "plus"
    public static let settings = "gearshape"

    public static let done = "checkmark.circle"
    public static let undo = "arrow.uturn.backward"
    public static let suggestion = "sparkles"
    public static let staleAttention = "clock.badge.exclamationmark"
    public static let aging = "clock"
    public static let due = "calendar"
    public static let dueToday = "calendar.badge.exclamationmark"
    public static let overdue = "exclamationmark.circle"
    public static let deferred = "arrow.uturn.up"
    public static let deferToReview = "arrow.uturn.right.circle"
    public static let stalled = "pause.circle"
    public static let weeklyReview = "checklist"
    public static let journaling = "pencil.and.scribble"
    public static let promoteStep = "arrow.up.right.circle"

    /// Inline checklist rows (A2, T21). Not yet in STYLEGUIDE §7 — flagged there is open;
    /// these are the stock SF Symbols pair for a checked/unchecked list item.
    public static let checkboxOn = "checkmark.square"
    public static let checkboxOff = "square"

    /// Reordering a list row (P6 step order). Like `checkbox*` above, STYLEGUIDE §7 has no
    /// entry for it; these are the stock chevrons, not an invented concept icon (T41).
    public static let moveUp = "chevron.up"
    public static let moveDown = "chevron.down"
    /// Settings → Contexts swipe action.
    public static let rename = "pencil"
    /// Routine runner: one step back.
    public static let back = "chevron.backward"

    public static let routineGeneric = "repeat"
    public static let routineMorning = "sunrise"
    public static let routineBedtime = "moon.stars"

    /// Routine icon by title, falling back to the generic one (STYLEGUIDE §7).
    public static func routine(title: String) -> String {
        switch title.lowercased() {
        case "morning": routineMorning
        case "bedtime": routineBedtime
        default: routineGeneric
        }
    }

    // MARK: Lists (§5a, T06)

    /// "Lists (and any custom list)" — the fallback for a list the table below has no entry for.
    public static let listBullet = "list.bullet"
    public static let listRead = "book"
    public static let listWatch = "play.rectangle"
    public static let listWish = "gift"

    /// The symbol for a list by name: the three named lists get their own glyph, any custom list
    /// falls back to `listBullet` (STYLEGUIDE §7 "Lists (and any custom list)"). Pure so the
    /// navbar's slot layout can be tested without SwiftUI.
    public static func list(named name: String) -> String {
        switch name.lowercased() {
        case "read": listRead
        case "watch": listWatch
        case "wish": listWish
        default: listBullet
        }
    }

    // MARK: Inbox step 1 kinds, navbar, required field (T06)

    /// Step-1 kind button: `Action`.
    public static let actionKind = "bolt"
    /// Step-1 kind button: `Knowledge / List`.
    public static let knowledgeOrListKind = "archivebox"
    /// Navbar's last slot, and the action-card `⋯` "File to" menu.
    public static let more = "ellipsis"
    /// Collapsing an opened card back to step 1 (distinct from the routine runner's `back`,
    /// which is a step-back chevron, not a card gesture).
    public static let collapse = "chevron.down"
    /// The leading glyph STYLEGUIDE §3.6 puts on a missing required field's label.
    public static let requiredField = "asterisk"
    /// Same glyph as `promoteStep` — STYLEGUIDE §7 lists them as one table entry ("Promote step /
    /// Make action"), because promoting a project step and making a list item into an action are
    /// the same gesture on two different kinds of note.
    public static let makeAction = promoteStep
}
