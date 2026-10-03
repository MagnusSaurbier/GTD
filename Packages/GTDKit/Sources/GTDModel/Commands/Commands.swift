import Foundation

// MARK: - Drafts

/// When to chase, and optionally who we are waiting on (W1, D39). The **follow-up date is
/// required**; `who` is free text and may be absent — plenty of waits are on a process, not a
/// person. Created only once the user has confirmed the date: the "+7 days" suggestion is UI
/// state until then (STYLEGUIDE §3.1).
public struct WaitingInfo: Sendable, Equatable, Codable, Hashable {
    /// Who or what the wait is on. `nil` (or blank) ⇒ no `waitingFor:` line is written at all.
    public var who: String?
    public var followUp: Day

    public init(who: String? = nil, followUp: Day) {
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
    /// I4a/R-8 — set **instead of** `project` when the user is creating the project in the same
    /// step (the `Create project "<text>"` row of the picker). Mirrors
    /// `ProjectDraft.newAreaTitle`: one command creates the project, links the action to it and
    /// files the card, so a crash can never leave a project without its first action.
    /// The project is created with a name only and lands area-less (P1, D35).
    public var newProjectTitle: String?
    public var deferDate: Day?
    public var due: Day?
    public var waiting: WaitingInfo?
    public var why: String
    public var what: String
    /// R-4 — the full capture text, kept as the note's first paragraph above `# Why?` when the
    /// title could not hold it (a long dictation, several lines). Empty otherwise.
    public var preamble: String

    public init(
        title: String,
        status: ActionStatus = .someday,
        contexts: [String] = [],
        timeEstimate: Int? = nil,
        project: NoteID? = nil,
        newProjectTitle: String? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        waiting: WaitingInfo? = nil,
        why: String = "",
        what: String = "",
        preamble: String = ""
    ) {
        self.title = title
        self.status = status
        self.contexts = contexts
        self.timeEstimate = timeEstimate
        self.project = project
        self.newProjectTitle = newProjectTitle
        self.deferDate = deferDate
        self.due = due
        self.waiting = waiting
        self.why = why
        self.what = what
        self.preamble = preamble
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

/// Where a Knowledge filing puts the note (I4b, D36). Reference material for a project is filed
/// through the Knowledge branch, so the folder picker offers the **active projects' folders**
/// next to the tree under `Knowledge/`.
public enum KnowledgeTarget: Sendable, Equatable, Codable, Hashable {
    /// A folder below `Knowledge/`, "/"-separated and relative to it; `""` is `Knowledge/` itself.
    case folder(String)
    /// The folder of an active project, named by its project note (`Projects/…/<P>/<P>.md`).
    case project(NoteID)
}

/// Where an inbox card goes when it leaves (I4).
///
/// **No decision carries a title** (R-4): every filed note keeps the inbox note's title, which is
/// its file name (C3). Editing the title on the card renames the inbox file first
/// (`renameInboxItem`), so there is only ever one title to keep in sync.
public enum InboxDecision: Sendable, Equatable, Codable {
    /// next / someday / waiting / done — the status lives in the draft, and so does the optional
    /// project chip (I4a). There is no Project *target* any more (R-8): a capture that is really
    /// a project stays an action and names the project it belongs to.
    case action(ActionDraft)
    /// I4b — `notes` is the optional notes panel and becomes the note's body.
    case knowledge(KnowledgeTarget, notes: String)
    /// I4b/§5a — the capture becomes one item of a list. `notes` is the optional notes panel and
    /// becomes the note's body; nothing about it is a commitment (L1).
    case list(name: String, notes: String)
    case trash
}

// MARK: - Commands

/// Every mutation in the app is exactly one of these. The reducer is the only place that
/// interprets them (ARCHITECTURE §4).
public enum GTDCommand: Sendable, Equatable {
    /// C3/R-4 — renames an inbox note: its title **is** its file name, so this moves
    /// `Inbox/<old>.md` to `Inbox/<title>.md`. An empty title is refused, a taken one is a
    /// `.titleCollision`.
    case renameInboxItem(NoteID, title: String)
    /// Replaces an inbox note's body (everything below the frontmatter). The title is not in it.
    case editInboxBody(NoteID, String)
    /// #85 — a half-processed card was closed: its body (lead + `Why?`/`What?`, `InboxBody`)
    /// and its chips are kept in the inbox note, which **stays in the inbox**, unprocessed.
    case saveInboxProgress(NoteID, InboxProgress)
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
    /// P6 — adds a step that points at an action note that already exists (`- [ ] Title →
    /// [[Action]]`), and links that action to the project. Refused when the action is closed,
    /// belongs to another project, or a step of this project already points at it (#61).
    case linkStep(project: NoteID, action: NoteID)

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
    /// R-5 — drops stored favourites whose list folder is gone (removed or renamed outside the
    /// app). Changes nothing — so writes nothing — when every favourite still has its folder.
    case pruneFavouriteLists
    /// L2 — the SF Symbol shown for a list; `nil` goes back to the built-in glyph.
    case setListIcon(list: String, symbol: String?)
    /// L1 — a new item typed inside the list itself (the `+` in the list view): a note
    /// `Lists/<name>/<title>.md` stamped `created` now, `notes` is the body. The other door for
    /// an item is the inbox (`fileInbox` → `.list`), which *moves* a capture instead.
    case addListItem(list: String, title: String, notes: String)
    /// Editing one item: a changed title renames its file, `notes` is the body.
    case updateListItem(NoteID, title: String, notes: String)
    /// L3 — checked off: the note moves to `Lists/<name>/Done/` and is kept as a log.
    case completeListItem(NoteID)
    /// I4c — the note moves to `GTD/Trash/`, like every other thing thrown away.
    case trashListItem(NoteID)
    /// L4 "Make action" — the note moves to `Actions/` and then obeys exactly the rules of an
    /// inbox action filing (required fields, the cap).
    case promoteListItem(NoteID, ActionDraft)
    /// E3 — the other door: an action dropped on a list becomes an item of that list. The note
    /// moves to `Lists/<name>/`, its `Why?`/`What?` text becomes the item's notes, and the
    /// action leaves every list, cap and signal it was in. `list` must exist (`createList`
    /// first); the item's title is the action's title.
    case moveActionToList(NoteID, list: String)
    case saveWeeklyReview(WeeklyReview)
    case logRoutineStep(routine: NoteID, stepID: String, RoutineStepResult)
    case setRoutineTime(routine: NoteID, DayTime?)
    case updateConfig(GTDConfig)
    case archiveCompleted
}

// MARK: - Errors and prompts

/// A field a tier demands before an action may enter it (I4, D12, R-3).
///
/// The cases are declared in the order the card shows them, and `GTDError.missingFields` keeps
/// that order, so "the first missing field" is the same field in the reducer, in the shake
/// animation and in the alert (STYLEGUIDE §3.6).
public enum RequiredField: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case why
    case what
    case context
    case timeEstimate
    case followUpDate
}

public enum GTDError: Error, Sendable, Equatable {
    /// I4, A3 — the UI must offer "demote something" or cancel. Never automatic (D14).
    case nextCapReached(cap: Int)
    /// I4/D12/R-3 — a **new** transition into a tier that demands more than the note carries:
    /// Next needs `Why?`, `What?`, at least one context and a time estimate; Someday needs
    /// `What?`; Waiting needs `What?` and a follow-up date. Done, lists, Knowledge and Trash
    /// need nothing, and a note **already** in a tier is never judged again (a waiting note
    /// without a follow-up date included) — the vault stays repairable. Carries every missing
    /// field, in `RequiredField` order.
    case missingFields([RequiredField])
    case notFound(NoteID)
    case titleCollision(String)
    case invalid(String)
}

extension RequiredField {

    /// R-3 — what a transition into `status` is still missing. Pure, so the card can ask the
    /// same question the reducer will answer (it is the reducer that refuses, STYLEGUIDE §3.6).
    ///
    /// - Parameter previous: the status the note has right now, or `nil` for a note that does
    ///   not exist yet. A status that is not *entering* its tier is left alone: notes that are
    ///   already in Next with gaps stay editable.
    public static func missing(
        status: ActionStatus,
        previous: ActionStatus?,
        why: String,
        what: String,
        contexts: [String],
        timeEstimate: Int?,
        followUpDate: Day?
    ) -> [RequiredField] {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var missing: [RequiredField] = []
        switch status {
        case .next, .inProgress:
            // `in-progress` is part of Next (A3), so entering it from outside Next asks the same.
            guard previous?.countsTowardCap != true else { return [] }
            if blank(why) { missing.append(.why) }
            if blank(what) { missing.append(.what) }
            if contexts.filter({ !blank($0) }).isEmpty { missing.append(.context) }
            if (timeEstimate ?? 0) <= 0 { missing.append(.timeEstimate) }
        case .someday:
            // Only a note that does not exist yet is asked for a `What?` here: a card being
            // filed, a list item being promoted. **Demoting is never blocked** — it is how an
            // over-cap or half-filled vault is repaired, and the review deck lives on it.
            if previous == nil, blank(what) { missing.append(.what) }
        case .waiting:
            if previous == nil, blank(what) { missing.append(.what) }
            // W1 — the follow-up date is the commitment, asked of every note *entering* waiting.
            // A note already waiting without one (M2 imports every legacy waiting item that
            // way) stays editable: refusing its context or time edit lost the edit and left the
            // gap in place, whereas the row's follow-up chip is how the gap gets filled.
            if previous != .waiting, followUpDate == nil { missing.append(.followUpDate) }
        case .done, .legacyTrashed:
            // A5/I4 — "I just did it" asks for nothing, and the legacy closed state is not
            // user-settable at all (R-1).
            break
        }
        return missing
    }
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
