import Foundation
import GTDModel

/// Where an existing action can be dropped: a sidebar section (Mac), or a `Move to…` menu
/// entry that is the drag's keyboard/VoiceOver twin on both platforms (STYLEGUIDE §8).
///
/// `projects` is the *section* — the person still has to say which project — while
/// `project(_:)` is one project row, which attaches directly. An action names at most one
/// project (`Action.project`), so attaching replaces whatever it named before.
public enum MoveDestination: Hashable, Sendable {
    case next
    case someday
    case waiting
    case projects
    case project(NoteID)
    /// The Lists *section* — the person picks the list (the inbox's own list picker).
    case lists
    /// One list by name: the action becomes an item of it (`moveActionToList`).
    case list(String)
    /// #87 — the In progress sidebar row / tab, and the board's first column.
    case inProgress
    /// #87 — the board's Agent column.
    case agent
    /// #87 — the board's Review column.
    case review
}

/// What a drop (or a `Move to…` choice) has to do, decided without SwiftUI so the rules are
/// unit-tested on Linux (ARCHITECTURE §5).
///
/// The reducer stays the authority over required fields and the cap (`Reducer.normalize`,
/// `checkCap`); this only decides *whether a dialogue is needed before sending*, so a drop that
/// needs nothing moves the item at once, and one that needs more opens the same action card the
/// inbox uses (STYLEGUIDE §3.5 step 2a) with the missing fields already marked.
public enum MovePlan: Equatable, Sendable {
    /// The item is already where it was dropped — nothing to do, and no drop highlight.
    case alreadyThere
    /// Nothing is missing: send this command.
    case perform(GTDCommand)
    /// The target tier needs fields the note does not have: open the action card, aimed at
    /// `status`, with `missing` marked (R-3, STYLEGUIDE §3.6).
    case card(status: ActionStatus, missing: [RequiredField])
    /// The Projects *section*: ask which project.
    case pickProject
    /// The Lists *section*: ask which list — the same picker as the inbox's `More…` sheet.
    case pickList

    /// Decides for `action` dropped on `destination`.
    public static func plan(
        action: Action, to destination: MoveDestination, snapshot: VaultSnapshot, today: Day
    ) -> MovePlan {
        // #86 — a deferral that is back sits in Next, so it is judged as a Next item.
        let status = Rules.effectiveStatus(action, today: today)
        switch destination {
        case .next:
            // `in-progress` is a Next item that has been started (A3): dropping it on Next
            // changes nothing.
            guard !status.countsTowardCap else { return .alreadyThere }
            return move(action, from: status, to: .next)
        case .someday:
            guard status != .someday else { return .alreadyThere }
            return move(action, from: status, to: .someday)
        case .waiting:
            guard status != .waiting else { return .alreadyThere }
            return move(action, from: status, to: .waiting)
        case .projects:
            return .pickProject
        case let .project(id):
            guard action.project != id else { return .alreadyThere }
            var updated = action
            updated.project = id
            return .perform(.updateAction(updated))
        case .lists:
            return .pickList
        case let .list(name):
            return .perform(.moveActionToList(action.id, list: name))
        case .inProgress:
            // "Begin action" (#87): from Next it is the A3 start; from anywhere else it enters
            // Next's tier, so the card asks what Next asks and the reducer checks the cap.
            guard status != .inProgress else { return .alreadyThere }
            return move(action, from: status, to: .inProgress)
        case .agent:
            guard status != .agent else { return .alreadyThere }
            return move(action, from: status, to: .agent)
        case .review:
            guard status != .review else { return .alreadyThere }
            return move(action, from: status, to: .review)
        }
    }

    /// Whether a drop on `destination` would do anything — what the sidebar tints on
    /// (`Color.accentWash`), so a row that would refuse the drop never invites it.
    public static func accepts(
        action: Action, destination: MoveDestination, snapshot: VaultSnapshot, today: Day
    ) -> Bool {
        plan(action: action, to: destination, snapshot: snapshot, today: today) != .alreadyThere
    }

    private static func move(
        _ action: Action, from previous: ActionStatus, to status: ActionStatus
    ) -> MovePlan {
        let missing = RequiredField.missing(
            status: status,
            previous: previous,
            why: action.why,
            what: action.what,
            contexts: action.contexts,
            timeEstimate: action.timeEstimate,
            // A tier change never carries the old follow-up along (`Reducer.normalize` clears
            // it outside Waiting), so Waiting always asks for its date (W1/D39).
            followUpDate: nil)
        guard missing.isEmpty else { return .card(status: status, missing: missing) }
        return .perform(.setStatus(action.id, status, waiting: nil))
    }
}
