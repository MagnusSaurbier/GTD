import Foundation
import GTDModel
import FeatureInbox

/// The pure half of the sweep (§10.1): turning a decision about one deferred inbox item, one
/// waiting item or one stalled project into exactly one `GTDCommand`.
///
/// Nothing here touches SwiftUI, so every branch is unit-tested against `AppModel` +
/// `InMemoryBackend`.

// MARK: - Deferred inbox items (§10.1.2, I5)

/// Filing a deferred item reuses the inbox card's vocabulary: the same eight targets
/// (`FeatureInbox.CardTarget`) and the same draft (`InboxSession.Draft`), so the review never
/// invents a second way to clarify an item.
public enum DeferredSweep {

    /// The targets the review offers for a deferred item. `deferToReview` is not among them —
    /// the item is already here, and parking it again would make the escape hatch a loop (I5).
    public static let targets: [CardTarget] = [
        .next, .someday, .waiting, .project, .knowledge, .trash,
    ]

    /// An `ActionDraft` built from the card draft, exactly as inbox filing builds one.
    public static func actionDraft(
        _ draft: InboxSession.Draft, status: ActionStatus, waiting: WaitingInfo? = nil
    ) -> ActionDraft {
        ActionDraft(
            title: draft.effectiveTitle,
            status: status,
            contexts: draft.contexts,
            timeEstimate: draft.timeBucket?.minutes,
            project: draft.project,
            deferDate: draft.deferDate,
            due: draft.due,
            waiting: waiting,
            why: draft.why,
            what: draft.what)
    }

    /// The decision for `target`, or `nil` when the target still needs something the user has
    /// not supplied (a knowledge folder, a project, the waiting pair) — the view opens the
    /// matching picker instead of guessing (§1 "no lying defaults").
    public static func decision(
        target: CardTarget,
        draft: InboxSession.Draft,
        waiting: WaitingInfo? = nil,
        knowledgeFolder: String? = nil,
        project: NoteID? = nil
    ) -> InboxDecision? {
        switch target {
        case .next, .someday:
            guard let status = target.status else { return nil }
            return .action(actionDraft(draft, status: status))
        case .trash:
            return .trash
        case .waiting:
            guard let waiting else { return nil }
            return .action(actionDraft(draft, status: .waiting, waiting: waiting))
        case .knowledge:
            guard let folder = knowledgeFolder, !folder.isEmpty else { return nil }
            return .knowledge(folder: folder, title: draft.effectiveTitle)
        case .project:
            guard let project else { return nil }
            return .existingProject(project, actions: [actionDraft(draft, status: .next)])
        case .deferToReview:
            return nil
        }
    }

    /// Next and Someday need a decision about the next physical action, same as the inbox card
    /// (STYLEGUIDE §3.6). Everything else may leave `What?` empty.
    public static func isComplete(_ draft: InboxSession.Draft, for target: CardTarget) -> Bool {
        guard target.requiresWhat else { return true }
        return !draft.what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Waiting (§10.1.3)

/// Chase · Bump · Resolve, the three things a weekly review does to a waiting item (§10.1.3).
///
/// Chase and bump both rewrite `followUpDate` — the difference is what the user just did, and
/// therefore which date is *suggested*: a chase has just happened, so the next check is close;
/// a bump is "not now", so it goes out a week. Neither date is written until the user confirms
/// it (STYLEGUIDE §3.1). Resolve moves the item to **Someday**, not Next: the wait ending is
/// not by itself a commitment, and Someday can never fail on the cap — the deck step that
/// follows immediately is where it earns a Next slot.
public enum WaitingSweep {
    public enum Choice: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
        case chase
        case bump
        case resolve

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .chase: ReviewCopy.chase
            case .bump: ReviewCopy.bump
            case .resolve: ReviewCopy.resolve
            }
        }

        public var hint: String {
            switch self {
            case .chase: ReviewCopy.chaseHint
            case .bump: ReviewCopy.bumpHint
            case .resolve: ReviewCopy.resolveHint
            }
        }

        public var symbol: String {
            switch self {
            case .chase: ReviewSymbols.chase
            case .bump: ReviewSymbols.waiting
            case .resolve: ReviewSymbols.demote
            }
        }

        /// True when the choice needs a follow-up date before it can be applied.
        public var needsFollowUp: Bool { self != .resolve }
    }

    /// The date offered as a dashed *suggestion* — never pre-written (STYLEGUIDE §3.1, W1).
    public static func suggestedFollowUp(for choice: Choice, today: Day) -> Day? {
        switch choice {
        case .chase: today.adding(days: 3)
        case .bump: WaitingInfo.suggestedFollowUp(from: today)
        case .resolve: nil
        }
    }

    /// The command, or `nil` when a chase/bump has no confirmed date yet, or the item has no
    /// "who" to keep waiting on (W1 — the pair is required, so the review cannot half-write it).
    public static func command(_ choice: Choice, action: Action, followUp: Day?) -> GTDCommand? {
        switch choice {
        case .resolve:
            return .setStatus(action.id, .someday, waiting: nil)
        case .chase, .bump:
            guard let followUp, let who = action.waitingFor, !who.isEmpty else { return nil }
            return .setStatus(action.id, .waiting, waiting: WaitingInfo(who: who, followUp: followUp))
        }
    }
}

// MARK: - Stalled projects (§10.1.4, P4)

/// A stalled project leaves the sweep in one of three ways: it gets an action (via
/// `FeatureProjects.WhatsNextSheet`, which promotes a step), or it stops claiming to be active.
public enum StalledSweep {
    public enum Choice: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
        /// Opens `WhatsNextSheet` — the project keeps its status and gains an action.
        case addNextAction
        case putOnHold
        case shelve

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .addNextAction: ReviewCopy.addNextAction
            case .putOnHold: ReviewCopy.putOnHold
            case .shelve: ReviewCopy.shelve
            }
        }

        public var symbol: String {
            switch self {
            case .addNextAction: ReviewSymbols.promote
            case .putOnHold: ReviewSymbols.stalled
            case .shelve: ReviewSymbols.someday
            }
        }

        public var status: ProjectStatus? {
            switch self {
            case .addNextAction: nil
            case .putOnHold: .onHold
            case .shelve: .someday
            }
        }
    }

    /// `nil` for `addNextAction`: that one is a sheet, not a command — the promotion it performs
    /// is `GTDCommand.promoteStep`, issued by `WhatsNextSheet`.
    public static func command(_ choice: Choice, project: Project) -> GTDCommand? {
        guard let status = choice.status, project.status != status else { return nil }
        var updated = project
        updated.status = status
        return .updateProject(updated)
    }
}
