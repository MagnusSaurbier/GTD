import Foundation

/// The canonical, exhaustive SF Symbols map (STYLEGUIDE §7). A concept missing here is added
/// to the style guide **first**, then to this file. Views never write a symbol name.
public enum Symbols {
    public static let inbox = "tray"
    public static let next = "arrow.right.circle"
    public static let backlog = "tray.full"
    public static let maybe = "moon.zzz"
    public static let waiting = "hourglass"
    public static let chase = "bell.badge"
    public static let projects = "square.stack"
    public static let area = "folder"
    public static let knowledge = "books.vertical"
    public static let trash = "trash"
    public static let capture = "plus.circle"
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
}
