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
/// review note, trash moves, archive moves.
public enum VaultFileOp: Sendable, Equatable {
    case put(path: String, text: String)
    case move(from: String, to: String)
    case delete(path: String)
}
