import Foundation
import GTDModel

/// The canonical user-facing strings of STYLEGUIDE §6.3 and the fixed vocabulary of §6.2.
/// Feature code contains no user-facing string literals — it references these.
///
/// They are plain `String`s, so they compile and are tested on Linux (ARCHITECTURE §5). The app
/// is English-only, so nothing resolves them through a catalog; turning them into
/// `LocalizedStringResource`s backed by each target's `Resources/Localizable.xcstrings` would
/// keep the same keys and change no call site.
public enum Copy {

    // MARK: Fixed vocabulary (§6.2) — never use a synonym

    public static let inbox = "Inbox"
    public static let next = "Next"
    /// The single "not now" tier (A3); the two older ones were merged into it.
    public static let someday = "Someday"
    public static let waiting = "Waiting"
    public static let project = "Project"
    /// Title of the projects **list** screen (the singular names one project or the field).
    public static let projects = "Projects"
    public static let area = "Area"
    public static let knowledge = "Knowledge"
    public static let trash = "Trash"
    public static let deferLabel = "Defer"
    /// The Deferred section — items hidden by a future `defer` (D1).
    public static let deferred = "Deferred"
    /// A row's context-menu submenu that twins the drag onto a sidebar section (E3, §8).
    public static let moveTo = "Move to"
    /// The note's `obsidian://` link, bottom of the action and project detail (`NoteFileLinks`).
    public static let openInObsidian = "Open in Obsidian"
    /// The note's absolute file path to the clipboard, to hand the ticket to a terminal or a
    /// `/do <path>` prompt.
    public static let copyPath = "Copy path"
    /// The `Move to` entry that asks which project: `Project…`.
    public static let projectEllipsis = "Project…"
    /// The `Move to` entry that asks which list: `List…`.
    public static let listEllipsis = "List…"
    public static let due = "Due"
    public static let followUp = "Follow-up"
    public static let chase = "Chase"
    public static let stalled = "Stalled"
    public static let routine = "Routine"
    /// Title of the routines **list** screen.
    public static let routines = "Routines"
    /// Leaves a run without completing it — never a second "Done" next to the step's own.
    public static let close = "Close"
    /// Routine runner: one step back, undoing a mis-tapped Done/Skip.
    public static let back = "Back"
    public static let weeklyReview = "Weekly review"
    public static let why = "Why?"
    public static let what = "What?"
    public static let processInbox = "Process inbox"
    public static let turnIntoProject = "Turn into project"
    public static let deferToReview = "Defer to review"
    public static let promote = "Promote"
    /// Accessibility label of a "New step" suggestion row (#61): linking that action as a step.
    public static func linkAsStep(_ title: String) -> String { "Link \(title) as a step" }
    public static let demote = "Demote"
    /// Review deck's fourth choice (STYLEGUIDE §3.10): leaves a card exactly where it is.
    public static let keep = "Keep"
    public static let done = "Done"
    public static let skip = "Skip"
    /// Row context menu (E1, T21) — start working on it now (→ `in-progress`).
    public static let start = "Start"
    /// Chase quick action (W2, T21) — whatever you were waiting for arrived.
    public static let resolved = "Resolved"
    /// Toolbar / `⌘N` quick capture (I7, T21).
    public static let quickCapture = "Quick capture"
    /// Generic fallback when a row action is refused and the reducer's own reason isn't
    /// meant for display (T21) — `GTDError.invalid`'s own text is shown instead when there is one.
    public static let actionFailed = "Couldn't complete that"
    public static let undo = "Undo"
    public static let clearFilters = "Clear filters"
    /// Filter-bar section headers on Next and Someday (E1): say what a picked chip means —
    /// contexts are *all* the ones at hand, time is the *most* that is free right now.
    public static let contextFilterHeader = "Context - pick all available right now"
    public static let timeFilterHeader = "Time - maximum available right now"
    /// The caption left of the collapse toggle while the filter chips are hidden (#36), and
    /// the toggle's spoken labels.
    public static let filters = "Filters"
    public static let hideFilters = "Hide filters"
    public static let showFilters = "Show filters"
    /// iPhone Next filter bar (E2): the switch that keeps the list to on-the-go contexts —
    /// on by default, off shows every context.
    public static let onlyMobile = "Only mobile"
    /// The `Lists` sidebar row / iPhone tab and the fixed-vocabulary singular "one list" term
    /// (§6.2: "List").
    public static let list = "List"
    public static let lists = "Lists"
    /// Step-1 kind button (T06, STYLEGUIDE §3.6/§7): "Action".
    public static let actionKind = "Action"
    /// Step-1 kind button and its opened card: "Knowledge / List".
    public static let knowledgeOrList = "Knowledge / List"
    public static let more = "More…"
    public static let makeAction = "Make action"
    public static let showDone = "Show done"

    // MARK: Canonical strings (§6.3)

    public static let whyPlaceholder = "What do I gain?"
    public static let whatPlaceholder = "The next physical action"
    /// W1/D39 — who is optional, and the field says so (STYLEGUIDE §6.3).
    public static let whoPlaceholder = "Who or what (optional)"
    /// Knowledge / List card's single body field (§3.5 step 2b).
    public static let notesPlaceholder = "Notes (optional)"
    public static let showAll = "Show all"
    /// Waiting sheet's save button — disabled until a follow-up date is confirmed (§3.6).
    public static let setWaiting = "Set waiting"
    /// The action-card `⋯` menu (§3.6): repeats the two swipe targets, Next / Someday.
    public static let fileTo = "File to"

    /// `3 of 14 left`
    public static func counter(remaining: Int, total: Int) -> String {
        "\(remaining) of \(total) left"
    }

    /// `Moved to Someday`
    public static func movedTo(_ destination: String) -> String { "Moved to \(destination)" }

    /// R-3 — the name of a field a tier is still missing (STYLEGUIDE §3.6, §6.2 vocabulary).
    public static func fieldName(_ field: RequiredField) -> String {
        switch field {
        case .why: why
        case .what: what
        case .context: "Context"
        case .timeEstimate: "Time"
        case .followUpDate: followUp
        }
    }

    /// `Still missing: Why?, Context, Time` — what the shell's alert says when a flow other
    /// than a card refuses (R-3; the cards mark their own fields instead).
    public static func missingFields(_ fields: [RequiredField]) -> String {
        "Still missing: " + fields.map(fieldName).joined(separator: ", ")
    }

    // The stale-write conflict sheet (N3, ARCHITECTURE §6 2026-09-25).
    public static let conflictTitle = "This note changed elsewhere"
    /// `“Edit ‘Call the bank’” could not be saved: …`
    public static func conflictBody(label: String) -> String {
        "\u{201C}\(label)\u{201D} could not be saved because the note changed in the vault first. "
            + "Edit the merged version below; Done writes it over both."
    }
    public static let conflictMine = "On this device"
    public static let conflictTheirs = "In the vault now"
    public static let conflictMerged = "Merged"
    public static let conflictTrashedHere = "Trashed on this device"
    public static let conflictGoneFromVault = "No longer in the vault"
    public static let keepVaultVersion = "Keep the vault's version"
    public static let titlePlaceholder = "Title"
    /// `2 passages changed on both sides; the vault's version was kept there.`
    public static func conflictHunks(_ count: Int) -> String {
        let passages = count == 1 ? "1 passage" : "\(count) passages"
        return "\(passages) changed on both sides; the vault's version was kept there."
    }

    // Text an earlier run never saved (#56).
    public static let unsavedTitle = "Text that wasn't saved"
    /// `GTD quit before saving what you typed in “Call the bank”.`
    public static func unsavedBody(note: String) -> String {
        "GTD quit before saving what you typed in \u{201C}\(note)\u{201D}. "
            + "Restore writes it into the note; Discard lets it go."
    }
    /// The note moved, was completed or trashed since: nothing to restore into.
    public static func unsavedNoteGone(note: String) -> String {
        "\u{201C}\(note)\u{201D} is no longer where it was. Copy the text and paste it where it belongs."
    }
    /// `2 of 3` — more than one note had unsaved text.
    public static func unsavedCounter(_ index: Int, of total: Int) -> String { "\(index) of \(total)" }
    public static let unsavedTyped = "What you typed"
    public static let restore = "Restore"
    public static let discard = "Discard"
    public static let copyText = "Copy text"
    public static let copied = "Copied"
    /// The journal file could not be read or written: typing is not being kept safe.
    public static func unsavedJournalFailed(_ reason: String) -> String {
        "GTD can't keep a safety copy of unsaved typing on this device: \(reason)"
    }

    public static let capSheetTitle = "Next is full"
    public static let capSheetBody = "Demote one to make room."
    public static let sendToSomedayInstead = "Send to Someday instead"
    /// The `Next is full` sheet's other exit (STYLEGUIDE §3.6: "Demote one … or cancel") and any
    /// other forced-choice sheet that needs a plain way out.
    public static let cancel = "Cancel"
    public static let deferToReviewPrompt = "Why doesn't this fit?"

    /// `What's next for <project>?` (P5)
    public static func whatsNext(project: String) -> String { "What's next for \(project)?" }

    public static let emptyNextTitle = "Nothing in Next"
    public static let emptyNextBody = "Promote from Someday, or process your inbox."
    public static let emptyNextFilteredTitle = "No match"
    public static let emptyNextFilteredBody = "Nothing in Next fits these filters."
    public static let emptySomedayTitle = "Nothing in Someday"
    public static let emptyWaitingTitle = "Not waiting on anyone"
    public static let emptyInboxTitle = "Inbox zero"
    public static let stalledProjectBody = "No open action. Add one or put the project on hold."

    /// `Nothing in Read` — an empty list, by name (§6.3 "Empty list").
    public static func emptyListTitle(_ list: String) -> String { "Nothing in \(list)" }

    /// Project picker, create row: `Create project "Renew passport"`.
    public static func createProject(_ text: String) -> String { "Create project \"\(text)\"" }

    /// Key-binding conflict (STYLEGUIDE §4.5): `Already used by Trash`.
    public static func alreadyUsedBy(_ command: String) -> String { "Already used by \(command)" }

    /// Undo toast, list filing (§6.3): `Added to Read`.
    public static func addedTo(_ list: String) -> String { "Added to \(list)" }

    /// The word VoiceOver adds to a missing required field's label (§3.6's asterisk, spelled out
    /// rather than left to the symbol alone — STYLEGUIDE §8 "colour/shape is never the only
    /// carrier"). `Why?, required`.
    public static func requiredFieldLabel(_ label: String) -> String { "\(label), required" }

    /// The review deck's Someday header (§3.10): count of items stale past the 30-day threshold.
    public static func untouchedOver30Days(_ count: Int) -> String {
        count == 1 ? "1 untouched > 30 days" : "\(count) untouched > 30 days"
    }

    /// `Morning done` / `Review complete` (§5 reward moments)
    public static func routineDone(_ routine: String) -> String { "\(routine) done" }
    public static let reviewComplete = "Review complete"
    /// `9 of 11 steps`
    public static func stepsSummary(done: Int, total: Int) -> String { "\(done) of \(total) steps" }
    /// `14 processed · 6 min` — the inbox-zero moment's stats line (STYLEGUIDE §5.1).
    public static func processedSummary(processed: Int, minutes: Int) -> String {
        "\(processed) processed · \(minutes) min"
    }

    /// `1 step left` / `5 steps left` — the projects-list counts line.
    public static func stepsLeft(_ count: Int) -> String {
        count == 1 ? "1 step left" : "\(count) steps left"
    }

    /// `2 active · 5 steps left` — the line under a project's name (STYLEGUIDE §3.4).
    public static func projectCounts(active: Int, remainingSteps: Int) -> String {
        metaLine(["\(active) active", stepsLeft(remainingSteps)])
    }

    /// The title of an **unset** "add a value" chip (`Area`, `Project`) as `ActionDetailView`'s
    /// single-value pickers draw it: the chip draws the `plus` symbol itself, so the title never
    /// carries a literal "+"; a leading one a caller passed is stripped, and the first letter is
    /// capitalised so every one of *these* reads the same.
    public static func unsetChipTitle(_ label: String) -> String {
        var text = label.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("+") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The title of an **unset** date/project **value chip** on the inbox card (`DateValueChip`,
    /// and the `+ project` chip step 2a draws with the same wording) — STYLEGUIDE §3.1/§3.5 spell
    /// these lower case: `+ defer` / `+ due` / `+ project`, unlike `unsetChipTitle`'s title-case
    /// `Area`/`Project` single-value chips in the Mac editor (T15 defect 9: these two were
    /// conflated and every value chip read `+ Defer` / `+ Due` / `+ Project`).
    public static func unsetValueChipTitle(_ label: String) -> String {
        var text = label.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("+") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    // MARK: Date picker (`DayPicker`)

    /// What the calendar popover/sheet is, for VoiceOver.
    /// The version stamp's spoken label (`VersionStamp`) — "Version 0.3".
    public static func version(_ short: String) -> String { "Version \(short)" }

    public static let pickADate = "Pick a date"
    public static let previousMonth = "Previous month"
    public static let nextMonth = "Next month"
    /// Back to the month the picker opened on — it moves the grid, it does not pick a date.
    public static let thisMonth = "Back to the selected month"

    /// One day cell, spoken: `Friday 25 September 2026`, and `today` / `tomorrow` for the two
    /// days that have their own word (STYLEGUIDE §8; same wording as `DateText.spelled`).
    public static func dayPickerCell(_ day: Day, today: Day) -> String {
        let date = "\(day.day) \(MonthGrid.spelledMonths[day.month - 1]) \(day.year)"
        let delta = day.days(since: today)
        switch delta {
        case 0: return "\(date), today"
        case 1: return "\(date), tomorrow"
        case -1: return "\(date), yesterday"
        default: return date
        }
    }

    public static let onTheRemarkable = "On the reMarkable"

    /// Chase quick action (W2, T21): `Bump +7d`.
    public static func bumpFollowUp(days: Int) -> String { "Bump +\(DateText.age(days: days))" }

    // MARK: Status names

    public static func status(_ status: ActionStatus) -> String {
        switch status {
        case .next: next
        case .someday: someday
        case .inProgress: "In progress"
        case .waiting: waiting
        case .done: done
        case .legacyTrashed: trash
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

    /// `Project name · mac · ≤30 min` — the metadata line under a row title. Missing values are
    /// simply left out, never written as "No project" or "0 min" (§1 "no lying defaults").
    public static func metaLine(_ parts: [String]) -> String {
        parts.joined(separator: " · ")
    }

    /// The same parts as one spoken phrase: VoiceOver reads a `·` as "middle dot" or swallows it,
    /// so the separator becomes a comma (STYLEGUIDE §8).
    public static func spoken(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: ", ")
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
