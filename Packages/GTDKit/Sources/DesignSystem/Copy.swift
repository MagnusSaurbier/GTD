import Foundation
import GTDModel

/// The canonical user-facing strings of STYLEGUIDE §6.3 and the fixed vocabulary of §6.2.
/// Feature code contains no user-facing string literals — it references these.
///
/// T12 turns them into `LocalizedStringResource`s backed by each target's
/// `Resources/Localizable.xcstrings`; the keys stay the same, so call sites do not change.
public enum Copy {

    // MARK: Fixed vocabulary (§6.2) — never use a synonym

    public static let inbox = "Inbox"
    public static let next = "Next"
    public static let backlog = "Backlog"
    public static let maybe = "Maybe"
    public static let waiting = "Waiting"
    public static let project = "Project"
    public static let area = "Area"
    public static let knowledge = "Knowledge"
    public static let trash = "Trash"
    public static let deferLabel = "Defer"
    public static let due = "Due"
    public static let followUp = "Follow-up"
    public static let chase = "Chase"
    public static let stalled = "Stalled"
    public static let routine = "Routine"
    public static let weeklyReview = "Weekly review"
    public static let why = "Why?"
    public static let what = "What?"
    public static let processInbox = "Process inbox"
    public static let turnIntoProject = "Turn into project"
    public static let deferToReview = "Defer to review"
    public static let promote = "Promote"
    public static let demote = "Demote"
    public static let done = "Done"
    public static let skip = "Skip"
    /// Row context menu (E1, T21) — start working on it now (→ `in-progress`).
    public static let start = "Start"
    /// Chase quick action (W2, T21) — whatever you were waiting for arrived.
    public static let resolved = "Resolved"
    /// Toolbar / `⌘N` quick capture (I7, T21).
    public static let quickCapture = "Quick capture"
    public static let undo = "Undo"
    public static let clearFilters = "Clear filters"

    // MARK: Canonical strings (§6.3)

    public static let whyPlaceholder = "What do I gain?"
    public static let whatPlaceholder = "The next physical action"
    public static let whoPlaceholder = "Who or what"
    public static let showAll = "Show all"

    /// `3 of 14 left`
    public static func counter(remaining: Int, total: Int) -> String {
        "\(remaining) of \(total) left"
    }

    /// `Moved to Backlog`
    public static func movedTo(_ destination: String) -> String { "Moved to \(destination)" }

    public static let capSheetTitle = "Next is full"
    public static let capSheetBody = "Demote one, or send this to Backlog."
    public static let sendToBacklogInstead = "Send to Backlog instead"
    public static let deferToReviewPrompt = "Why doesn't this fit?"

    /// `What's next for <project>?` (P5)
    public static func whatsNext(project: String) -> String { "What's next for \(project)?" }

    public static let emptyNextTitle = "Nothing in Next"
    public static let emptyNextBody = "Promote from Backlog, or process your inbox."
    public static let emptyNextFilteredTitle = "No match"
    public static let emptyNextFilteredBody = "Nothing in Next fits these filters."
    public static let emptyWaitingTitle = "Not waiting on anyone"
    public static let emptyInboxTitle = "Inbox zero"
    public static let stalledProjectBody = "No open action. Add one or put the project on hold."

    /// `Morning done` / `Review complete` (§5 reward moments)
    public static func routineDone(_ routine: String) -> String { "\(routine) done" }
    public static let reviewComplete = "Review complete"
    /// `9 of 11 steps`
    public static func stepsSummary(done: Int, total: Int) -> String { "\(done) of \(total) steps" }

    public static let onTheRemarkable = "On the reMarkable"

    /// Chase quick action (W2, T21): `Bump +7d`.
    public static func bumpFollowUp(days: Int) -> String { "Bump +\(DateText.age(days: days))" }

    // MARK: Status names

    public static func status(_ status: ActionStatus) -> String {
        switch status {
        case .next: next
        case .backlog: backlog
        case .maybe: maybe
        case .inProgress: "In progress"
        case .waiting: waiting
        case .done: done
        case .trash: trash
        }
    }

    public static func projectStatus(_ status: ProjectStatus) -> String {
        switch status {
        case .active: "Active"
        case .onHold: "On hold"
        case .someday: "Someday"
        case .done: done
        }
    }

    /// `≤10` `≤30` `≤60` `60+` (STYLEGUIDE §3.5)
    public static func timeBucket(_ bucket: TimeBucket) -> String {
        switch bucket {
        case .upTo10: "≤10"
        case .upTo30: "≤30"
        case .upTo60: "≤60"
        case .over60: "60+"
        }
    }
}

/// Date and age wording (STYLEGUIDE §6.3): relative within 7 days (`today`, `tomorrow`, `Thu`),
/// otherwise `25 Sep`; ages as `16d`. Written without `DateFormatter` so the output is identical
/// on every platform and in every locale — the app is English-only (§6.1).
public enum DateText {
    static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// `today` · `tomorrow` · `Thu` · `25 Sep`.
    public static func short(_ day: Day, today: Day) -> String {
        let delta = day.days(since: today)
        switch delta {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6: return weekdays[day.isoWeekday - 1]
        default: return "\(day.day) \(months[day.month - 1])"
        }
    }

    /// `16d` — the badge form of an age.
    public static func age(days: Int) -> String { "\(days)d" }

    /// `16 days old` — what VoiceOver reads (STYLEGUIDE §8).
    public static func spelledAge(days: Int) -> String {
        days == 1 ? "1 day old" : "\(days) days old"
    }

    /// `Thursday` — VoiceOver reads badges in full words.
    public static func spelled(_ day: Day, today: Day) -> String {
        let delta = day.days(since: today)
        switch delta {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6:
            let full = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            return full[day.isoWeekday - 1]
        default: return "\(day.day) \(months[day.month - 1])"
        }
    }
}
