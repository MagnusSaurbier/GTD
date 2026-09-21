import Foundation
import GTDModel
import DesignSystem

/// Strings the weekly review needs that are not part of the shared vocabulary in
/// `DesignSystem.Copy` (STYLEGUIDE §6.2/§6.3). Feature code never writes a user-facing literal,
/// so every one of them lives here — the same split `FeatureInbox.InboxCopy` uses.
///
/// Wording follows §6.1: English, sentence case, verb-first buttons, no praise, no exclamation
/// marks, and the fixed GTD vocabulary wherever one exists (`Next`, `Someday`,
/// `Promote`, `Demote`, `Chase`, `Stalled`, `Weekly review`).
public enum ReviewCopy {

    // MARK: Wizard frame

    /// `KW 38 · 2026` — the review note's week, and the wizard's subtitle.
    public static func weekLabel(year: Int, week: Int) -> String { "KW \(week) · \(year)" }

    public static let back = "Back"
    public static let cont = "Continue"
    public static let quit = "Quit"
    public static let resume = "Resume"
    public static let saveAndFinish = "Save and finish"
    public static let finish = "Finish"

    /// Shown by the shell while a review is in progress (`ReviewResumeBanner`).
    public static let resumeBannerTitle = "Weekly review in progress"
    public static func resumeBannerDetail(year: Int, week: Int) -> String {
        weekLabel(year: year, week: week)
    }

    /// A saved session from an earlier week: never silently adopted, never silently dropped.
    public static let staleTitle = "Unfinished review"
    public static func staleBody(year: Int, week: Int) -> String {
        "\(weekLabel(year: year, week: week)) was never finished."
    }
    public static let staleContinue = "Continue it"
    public static let staleDiscard = "Discard it"

    // MARK: Stages and steps (rail)

    public static let stageSweep = "Sweep"
    public static let stageDeck = "Deck"
    public static let stageSystemsCheck = "Systems check"
    public static let stageReflection = "Reflection"
    public static let stageSummary = "Summary"

    public static let stepInbox = "Inbox to zero"
    public static let stepDeferred = "Deferred to review"
    public static let stepWaiting = "Waiting"
    public static let stepStalled = "Stalled projects"
    public static let stepDeckNext = "Next"
    public static let stepDeckSomeday = "Someday"
    public static let stepDeckProjects = "Projects on hold"

    // MARK: Gates

    public static func inboxNotEmpty(_ remaining: Int) -> String {
        "\(remaining) left in the inbox. Process them to continue."
    }
    public static func overCap(count: Int, cap: Int) -> String {
        "Next holds \(count) of \(cap). Demote before continuing."
    }

    // MARK: Sweep

    public static let deferredReasonLabel = "Why it did not fit"
    public static let systemFixLabel = "System fix"
    public static let systemFixPlaceholder = "What would stop this happening again?"
    public static let noDeferredTitle = "Nothing deferred"
    public static let noDeferredBody = "No item was parked for this review."
    public static let noWaitingTitle = Copy.emptyWaitingTitle
    public static let noWaitingBody = "Nothing to chase this week."
    public static let noStalledTitle = "No stalled project"
    public static let noStalledBody = "Every active project has an open action."
    public static let inboxZeroBody = "The queue is empty — continue."

    public static let chase = Copy.chase
    public static let bump = "Bump"
    public static let resolve = "Resolve"
    public static let chaseHint = "Chased today — pick the next follow-up."
    public static let bumpHint = "Not chasing — push the follow-up out."
    public static let resolveHint = "The wait is over — moves to Someday."

    public static let addNextAction = "Add next action"
    public static let putOnHold = "Put on hold"
    public static let shelve = "Move to Someday"
    public static let keep = "Keep"

    public static func waitingSince(days: Int) -> String {
        days == 1 ? "waiting 1 day" : "waiting \(days) days"
    }

    // MARK: Deck

    public static let deckNextTitle = "Keep or demote"
    public static let deckSomedayTitle = "Promote, keep or trash"
    public static let deckProjectsTitle = "Activate, keep or drop"
    public static let activateChoice = "Activate"
    public static let dropChoice = "Drop"
    public static func deckCounter(done: Int, total: Int) -> String { "\(done) of \(total)" }
    public static let deckDoneTitle = "Deck clear"
    public static let deckDoneBody = "Every card in this phase has a decision."

    /// R-3 — a promote the reducer refused for missing fields (STYLEGUIDE §3.10): the card names
    /// them (`Copy.missingFields`) and offers to open the action or keep it as is.
    public static let editAction = "Edit"
    public static let keepDespiteMissingFields = keep

    /// The cap sheet's list header when a promote from the deck is what triggered it (D14) — the
    /// body and title themselves are `Copy.capSheetTitle`/`Copy.capSheetBody`, shared with the
    /// inbox's own cap sheet.
    public static let capSheetDemote = Copy.demote
    public static let capSheetCancel = "Cancel"

    // MARK: Systems check (§10.3 prompts)

    public static let promptTrust = "Trust in inbox, Next and triggers — did anything slip?"
    public static let promptWorkload = "Is the workload manageable or piling up?"
    public static let promptRoutines = "Are the routines working?"

    public static let statCaptured = "Captured"
    public static let statProcessed = "Processed"
    public static let statDone = "Done this week"
    public static let statNextAge = "Median age in Next"
    public static let statUntouched = "Untouched over 30 days"
    public static let statWaiting = "Waiting"
    public static let statStalled = Copy.stalled

    /// The captured/processed pair is an approximation — the vault keeps no filed-at timestamp,
    /// so it is labelled as one instead of being presented as an audit trail (GTDStats README).
    public static let capturedApproximation =
        "Captured and processed are approximate: the vault stores no filed-at time, so items "
        + "captured in an earlier week, trashed, or filed into Knowledge are not counted."

    public static let routineAuditTitle = "Routine audit"
    public static let noRoutinesTitle = "No routines"
    public static let noRoutinesBody = "Add a routine template in the vault to see the audit."

    /// `▲ 3 vs last week` / `▼ 2 vs last week` / `no change vs last week` (STYLEGUIDE §3.10 —
    /// trends are never coloured, so the arrow carries the direction on its own).
    public static func trend(_ delta: Int, unit: String = "") -> String {
        let suffix = unit.isEmpty ? "" : " \(unit)"
        if delta == 0 { return "no change vs last week" }
        let arrow = delta > 0 ? "▲" : "▼"
        return "\(arrow) \(abs(delta))\(suffix) vs last week"
    }

    public static func percent(_ value: Int) -> String { "\(value)%" }
    public static func days(_ value: Int) -> String { DateText.age(days: value) }

    public static let heatmapLegendDone = Copy.done
    public static let heatmapLegendSkipped = Copy.skip
    public static let heatmapLegendNoData = "Not logged"

    /// Column headers of the heatmap: one initial per weekday, Monday first (§3.10).
    public static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    // MARK: Reflection (§10.4)

    public static let remarkableReminderTitle = "Review the journal"
    public static let remarkableReminderBody =
        "Read this week's handwritten notes before answering. " + Copy.onTheRemarkable

    public static let questionWantedToAchieve = "What did I want to achieve?"
    public static let questionAchieved = "What did I achieve?"
    public static let questionBehaviorToChange = "Which behavior do I want to change?"
    public static let questionWhatToStop = "What do I want to stop?"
    public static let questionHowIGrew = "How did I grow?"
    public static let questionHowToGrowFurther = "How do I want to grow further?"
    public static let questionWhatToTry = "What do I want to try out?"
    public static let questionGoalForNextWeek = "Goal for next week"

    /// Last week's goal, shown next to "What did I want to achieve?" (§10.4).
    public static func lastWeeksGoal(week: Int) -> String { "Goal set in KW \(week)" }
    public static let noLastReview = "No earlier review in the vault."

    // MARK: Summary

    public static let summaryTitle = "What changed"
    public static let summaryProcessed = "Inbox processed"
    public static let summaryDeferred = "Deferred items handled"
    public static let summaryWaiting = "Waiting items handled"
    public static let summaryDemoted = "Demoted"
    public static let summaryPromoted = "Promoted"
    public static let summaryTrashed = "Trashed"
    public static let summaryProjects = "Projects touched"
    public static func savedAs(year: Int, week: Int) -> String {
        "Saved as \(VaultLayout.default.reviewPath(year: year, week: week).path)"
    }

    // MARK: Errors

    /// A refused command, worded for the review screen. Inline text, never an alert
    /// (STYLEGUIDE §4.3).
    public static func errorText(_ error: GTDError) -> String {
        switch error {
        case let .nextCapReached(cap):
            "\(Copy.capSheetTitle) (\(cap)). \(Copy.capSheetBody)"
        case let .missingFields(fields):
            Copy.missingFields(fields)
        case .notFound:
            "That note is no longer in the vault."
        case let .titleCollision(title):
            "A note called \(title) already exists."
        case let .invalid(message):
            message
        }
    }

    // MARK: Notes written into the review note

    /// One `systemFixNotes` line per deferred item (I5): what it was, why it did not fit, and
    /// the fix the user decided on.
    public static func systemFixNote(item: String, reason: String, fix: String) -> String {
        let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let howToFix = fix.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = text
        if !why.isEmpty { line += " (deferred: \(why))" }
        if !howToFix.isEmpty { line += " → \(howToFix)" }
        return line
    }

    /// A systems-check answer keeps its prompt, otherwise the note is unreadable a year later.
    public static func systemsCheckNote(prompt: String, answer: String) -> String {
        "\(prompt) \(answer.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

/// Symbols the review needs, resolved through the canonical map of STYLEGUIDE §7 so no view
/// writes a raw symbol string. Nothing new is invented — each one maps to a §7 entry.
public enum ReviewSymbols {
    public static let review = Symbols.weeklyReview
    public static let deferred = Symbols.deferToReview
    public static let journaling = Symbols.journaling
    public static let stalled = Symbols.stalled
    public static let waiting = Symbols.waiting
    public static let chase = Symbols.chase
    public static let inbox = Symbols.inbox
    public static let promote = Symbols.promoteStep
    public static let demote = Symbols.someday
    public static let keep = Symbols.next
    public static let trash = Symbols.trash
    public static let projects = Symbols.projects
    public static let someday = Symbols.someday
    public static let done = Symbols.done
}
