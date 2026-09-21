import Foundation

// MARK: - Drafts

/// Who we are waiting for and when to chase (W1). Created only once the user has confirmed
/// both halves — the "+7 days" suggestion is UI state until then (STYLEGUIDE §3.1).
public struct WaitingInfo: Sendable, Equatable, Codable, Hashable {
    public var who: String
    public var followUp: Day

    public init(who: String, followUp: Day) {
        self.who = who
        self.followUp = followUp
    }

    /// The date offered as a *suggestion* in the waiting sheet. Never written without confirmation.
    public static func suggestedFollowUp(from today: Day) -> Day { today.adding(days: 7) }
}

/// What the user decided about one action, before it has a file. Undecided fields stay empty.
public struct ActionDraft: Sendable, Equatable, Codable {
    public var title: String
    public var status: ActionStatus
    public var contexts: [String]
    public var timeEstimate: Int?
    public var project: NoteID?
    public var deferDate: Day?
    public var due: Day?
    public var waiting: WaitingInfo?
    public var why: String
    public var what: String

    public init(
        title: String,
        status: ActionStatus = .someday,
        contexts: [String] = [],
        timeEstimate: Int? = nil,
        project: NoteID? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        waiting: WaitingInfo? = nil,
        why: String = "",
        what: String = ""
    ) {
        self.title = title
        self.status = status
        self.contexts = contexts
        self.timeEstimate = timeEstimate
        self.project = project
        self.deferDate = deferDate
        self.due = due
        self.waiting = waiting
        self.why = why
        self.what = what
    }
}

/// A new project, optionally in a new area (P1).
public struct ProjectDraft: Sendable, Equatable, Codable {
    public var title: String
    public var area: NoteID?
    /// Set instead of `area` when the user is creating the area in the same step.
    public var newAreaTitle: String?
    public var outcome: String
    public var why: String
    public var steps: [String]

    public init(
        title: String,
        area: NoteID? = nil,
        newAreaTitle: String? = nil,
        outcome: String = "",
        why: String = "",
        steps: [String] = []
    ) {
        self.title = title
        self.area = area
        self.newAreaTitle = newAreaTitle
        self.outcome = outcome
        self.why = why
        self.steps = steps
    }
}

/// Where an inbox card goes when it leaves (I4).
public enum InboxDecision: Sendable, Equatable, Codable {
    /// next / someday / waiting / done — the status lives in the draft.
    case action(ActionDraft)
    case knowledge(folder: String, title: String)
    /// I4b/§5a — the capture becomes one item of a list. `notes` is the optional notes panel and
    /// becomes the note's body; nothing about it is a commitment (L1).
    case list(name: String, title: String, notes: String)
    case newProject(ProjectDraft, firstActions: [ActionDraft])
    case existingProject(NoteID, actions: [ActionDraft])
    case trash
}

// MARK: - Commands

/// Every mutation in the app is exactly one of these. The reducer is the only place that
/// interprets them (ARCHITECTURE §4).
public enum GTDCommand: Sendable, Equatable {
    case editInboxText(NoteID, String)
    case fileInbox(NoteID, InboxDecision)
    case deferInboxToReview(NoteID, reason: String)
    case createAction(ActionDraft)
    case updateAction(Action)
    case setStatus(NoteID, ActionStatus, waiting: WaitingInfo?)
    /// I4c — trashing an action. Trash is **not a status**: the note leaves the snapshot and
    /// `GTDVault` moves the file into `GTD/Trash/`. Nothing is ever hard-deleted, so undo works.
    case trashAction(NoteID)
    case complete(NoteID)
    case toggleCheckbox(NoteID, index: Int)
    case convertActionToProject(NoteID, ProjectDraft)
    case createArea(title: String)
    case createProject(ProjectDraft)
    case updateProject(Project)
    case promoteStep(project: NoteID, stepIndex: Int, ActionDraft)

    // MARK: Lists (§5a)

    /// L2 — creates `Lists/<name>/`. The folder *is* the list, so this is the one command whose
    /// only effect is a folder.
    case createList(name: String)
    /// L2 — renames the folder, carrying every item with it (`VaultFileOp.moveFolder`, R-5).
    case renameList(from: String, to: String)
    /// L2/R-5 — moves the whole list folder into `GTD/Trash/`, items included. Never a delete,
    /// always undoable.
    case removeList(name: String)
    /// I4b — the lists shown in the inbox navbar, in the user's order (R-5).
    case setFavouriteLists([String])
    /// Editing one item: a changed title renames its file, `notes` is the body.
    case updateListItem(NoteID, title: String, notes: String)
    /// L3 — checked off: the note moves to `Lists/<name>/Done/` and is kept as a log.
    case completeListItem(NoteID)
    /// I4c — the note moves to `GTD/Trash/`, like every other thing thrown away.
    case trashListItem(NoteID)
    /// L4 "Make action" — the note moves to `Actions/` and then obeys exactly the rules of an
    /// inbox action filing (required fields, the cap).
    case promoteListItem(NoteID, ActionDraft)
    case saveWeeklyReview(WeeklyReview)
    case logRoutineStep(routine: NoteID, stepID: String, RoutineStepResult)
    case setRoutineTime(routine: NoteID, DayTime?)
    case updateConfig(GTDConfig)
    case archiveCompleted
}

// MARK: - Errors and prompts

public enum GTDError: Error, Sendable, Equatable {
    /// I4, A3 — the UI must offer "demote something" or cancel. Never automatic (D14).
    case nextCapReached(cap: Int)
    /// W1 — `waiting` needs both who and follow-up date.
    case waitingInfoRequired
    case notFound(NoteID)
    case titleCollision(String)
    case invalid(String)
}

/// Something the reducer asks the app shell to present. Not an error, not a view concern.
public enum AppPrompt: Sendable, Equatable {
    /// P5 — completing an action that belongs to a project.
    case whatsNext(project: NoteID)
}

/// A file-level effect that is not implied by the snapshot diff: knowledge notes, the weekly
/// review note, trash moves, archive moves, folder moves.
///
/// There is deliberately **no hard delete**: `.delete` is performed by `GTDVault` as a move into
/// `GTD/Trash/` (ARCHITECTURE §4), and `.moveFolder` is a rename, never a removal.
public enum VaultFileOp: Sendable, Equatable {
    case put(path: String, text: String)
    case move(from: String, to: String)
    /// Moves a whole directory and everything below it in one step (R-5): renaming a list,
    /// removing a list (into `GTD/Trash/`) and re-assigning a project's area. It never
    /// overwrites — a destination that already exists, as a file *or* a folder, is
    /// `VaultError.destinationExists` — and its inverse is the move back, so it undoes and rolls
    /// back like every other op.
    case moveFolder(from: String, to: String)
    /// Creates an (empty) directory, intermediate folders included — what `createList` needs,
    /// because a list *is* its folder (L2) and an empty folder is not expressible as a file.
    ///
    /// It is idempotent, and its **inverse is nothing**: removing a directory would be the hard
    /// delete this vault never does, so an undo (or a rollback) leaves the empty folder behind.
    /// That is why `createList` is not undoable (`Rules.isUndoable`) — see ARCHITECTURE §6.
    case createFolder(path: String)
    case delete(path: String)
}
