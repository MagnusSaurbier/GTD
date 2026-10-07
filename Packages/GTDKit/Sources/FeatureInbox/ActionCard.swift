import Foundation
import GTDModel
import GTDAppCore
import DesignSystem

// The opened action card, as data and rules rather than as a view (STYLEGUIDE §3.5 step 2a,
// §3.6's second table). **Two** owners drive exactly this code: `InboxSession` (a capture being
// processed) and `MakeActionModel` (L4's "Make action" on a list item). Neither re-implements a
// required field, the cap flow or the asterisk rule — they share what is in this file.

// MARK: - Draft

/// What the user has decided about the card in front of them. Nothing here is written to the
/// vault until the card is filed, and nothing is pre-filled (§1 "no lying defaults").
public struct InboxDraft: Sendable, Equatable {
    /// The note's title, editable in place. For an inbox card it is the **file name** (C3): a
    /// changed title renames `Inbox/<title>.md` before the card is filed. For L4's "Make action"
    /// it is the list item's title.
    public var title: String
    /// The inbox note's body — what is below its frontmatter. Often empty: a capture keeps its
    /// text in the title and only writes a body when the title could not carry all of it.
    public var body: String
    public var why: String
    public var what: String
    /// I4b — the optional notes panel of the opened Knowledge / List card (step 2b). It survives
    /// a collapse like every other field, and only the Knowledge / list exits send it.
    public var notes: String
    public var contexts: [String]
    public var timeBucket: TimeBucket?
    public var deferDate: Day?
    public var due: Day?
    /// I4a — the `+ project` chip: an existing project…
    public var project: NoteID?
    /// …or one the picker is creating with this name (R-8). Never both.
    public var newProjectTitle: String?

    public init(
        title: String = "",
        body: String = "",
        why: String = "",
        what: String = "",
        notes: String = "",
        contexts: [String] = [],
        timeBucket: TimeBucket? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        project: NoteID? = nil,
        newProjectTitle: String? = nil
    ) {
        self.title = title
        self.body = body
        self.why = why
        self.what = what
        self.notes = notes
        self.contexts = contexts
        self.timeBucket = timeBucket
        self.deferDate = deferDate
        self.due = due
        self.project = project
        self.newProjectTitle = newProjectTitle
    }

    /// A capture as the card opens it. A card that was closed half-way (#85) kept its `Why?` /
    /// `What?` in the note's body and its chips in the frontmatter, so it opens with them again;
    /// `body` is then only the capture text above the headings (`InboxBody`).
    public init(item: InboxItem) {
        let stored = InboxBody.read(item.body)
        self.init(
            title: item.title,
            body: stored.lead,
            why: stored.why,
            what: stored.what,
            contexts: item.contexts,
            timeBucket: TimeBucket(minutes: item.timeEstimate),
            deferDate: item.deferDate,
            due: item.due,
            project: item.project)
    }

    /// #85 — what closing the card keeps in the inbox note `stored`: the body with `Why?` /
    /// `What?` written in (only the pieces that changed, `InboxBody.written(over:)`) and the
    /// chips. The notes panel of the Knowledge / List card has no place of its own in an inbox
    /// note, so it joins the capture text — exactly where a Knowledge or list filing would put
    /// it. A project the picker was about to create is not kept: it does not exist yet.
    public func progress(over stored: InboxItem) -> InboxProgress {
        let lead = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? body : CaptureText.filedBody(body: body, notes: notes)
        // A stored estimate the chip shows as its bucket (45 → `60`) is kept as written.
        let minutes = TimeBucket(minutes: stored.timeEstimate) == timeBucket
            ? stored.timeEstimate : timeBucket?.minutes
        return InboxProgress(
            body: InboxBody(lead: lead, why: why, what: what).written(over: stored.body),
            contexts: contexts,
            timeEstimate: minutes,
            project: project,
            deferDate: deferDate,
            due: due)
    }

    /// L4 — "Make action" starts from the list item: its title is kept, and so are its notes
    /// (the reducer puts them above the action's headings).
    public init(item: ListItem) {
        self.init(title: item.title, notes: item.notes)
    }

    /// A drop onto a section that needs more than the note has (`MovePlan.card`): the card
    /// starts from everything the action already carries, so the person only fills the gap.
    /// The preamble (R-4) is the body the card shows above `Why?`.
    public init(action: Action) {
        self.init(
            title: action.title,
            body: action.preamble,
            why: action.why,
            what: action.what,
            contexts: action.contexts,
            timeBucket: action.timeBucket,
            deferDate: action.deferDate,
            due: action.due,
            project: action.project)
    }

    /// The file name the title field would give the note — sanitised and cut like a capture
    /// (`CaptureText.renamedTitle`). `nil` while the field is only whitespace, which is the one
    /// title that is refused.
    public var noteTitle: String? { CaptureText.renamedTitle(title) }

    /// True when the card has a body worth showing: not empty, and not just the Why/What
    /// template skeleton an Obsidian-made note carries (`CaptureText.isEmptyBody`).
    public var hasBodyContent: Bool { !CaptureText.isEmptyBody(body) }

    /// A2 — a second checkbox in *What?* offers "Turn into project".
    public var suggestsProject: Bool { Checkbox.scan(what).count >= 2 }

    /// True while the user has changed nothing about this card.
    public func isPristine(for item: InboxItem) -> Bool {
        self == InboxDraft(item: item)
    }

    /// Builds the command payload. Suggestions are never in here — only confirmed values.
    public func actionDraft(status: ActionStatus, waiting: WaitingInfo? = nil) -> ActionDraft {
        ActionDraft(
            // The inbox reducer files under the note's (already renamed) file name and ignores
            // this; L4's "Make action" uses it. Either way it is the title the card shows.
            title: title,
            status: status,
            contexts: contexts,
            timeEstimate: timeBucket?.minutes,
            project: project,
            newProjectTitle: newProjectTitle,
            deferDate: deferDate,
            due: due,
            waiting: waiting,
            why: why,
            what: what)
    }

    /// I4a/R-8 — the `+ project` chip. The card **stays an action**: it names a project instead
    /// of turning into one (D33). Nothing is written until the card is filed.
    public mutating func chooseProject(_ id: NoteID?) {
        project = id
        newProjectTitle = nil
    }

    /// The picker's `Create project "<text>"` row: the project is created with a name only, in
    /// the same command that files the card (R-8). A blank name is ignored.
    public mutating func createProject(named title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        project = nil
        newProjectTitle = clean
    }

    /// What the chip shows: the chosen project's title, the name being created, or `nil`.
    public func projectChipTitle(in snapshot: VaultSnapshot) -> String? {
        if let newProjectTitle { return newProjectTitle }
        guard let id = project else { return nil }
        return snapshot.project(id)?.title ?? id.title
    }
}

// MARK: - Refusals

/// Every way the card can say no. One case per refusal the state machine can produce, so a test
/// can name the one it expects instead of asserting "nothing happened".
public enum InboxRefusal: Sendable, Equatable {
    /// There is no card (inbox zero, or the item vanished from the vault).
    case noCard
    /// The exit does not belong to the step the card is in — Trash from an opened card, `Next`
    /// from step 1 (STYLEGUIDE §3.6: "Trash and Defer are reachable only from step 1").
    case notAvailable(InboxExit, in: InboxStep)
    /// R-3/D12 — the tier the card is leaving to needs fields the draft does not have. Every one
    /// of them is listed, in `RequiredField` order, so the card can mark each.
    case missing([RequiredField])
    /// Defer to review needs a reason (I5).
    case reasonRequired
    /// I4/A3 — Next is full: demote one, or cancel. Never automatic (D14).
    case capReached(cap: Int)
    /// Anything else the reducer refused (a title collision, say).
    case failed(GTDError)
}

// MARK: - The card's state

/// Draft **plus** the two things STYLEGUIDE §3.6's validation paragraph asks the card to
/// remember: which fields are marked, and that it should shake. A value type, so both owners can
/// hold one and every rule below is testable without a view or a backend.
public struct ActionCardState: Sendable, Equatable {

    /// What is filed when the card leaves. Kept across a collapse (STYLEGUIDE §3.6: "the draft
    /// survives until the card is filed or the session ends").
    public var draft: InboxDraft

    /// Fields the last refusal named. They stay marked **until the field is filled** rather than
    /// until the next attempt, which is what "every missing field shows a leading asterisk on its
    /// label until it is filled" means — read it through `missingFields` / `isMissing(_:)`.
    public private(set) var flagged: Set<RequiredField>

    /// Bumped on every refusal, so a repeated one animates again (`View.shake(trigger:)`).
    public private(set) var shakeTrigger: Int

    /// The first missing **text** field, for the card to focus. `nil` when only a chip group is
    /// missing — nothing to put a caret in.
    public private(set) var focusRequest: RequiredField?

    /// STYLEGUIDE §3.6 — swipes are off while a field has the keyboard, and so are the single
    /// keys. The view sets it; the model is what `DragResolver`/`KeyMap` are asked about.
    public var isFieldFocused: Bool

    /// The Next items offered for demotion while the cap sheet is up (I4, A3). Empty otherwise.
    public var capCandidates: [Action]

    /// What the cap sheet would file once a slot is free.
    public var pending: PendingFiling?

    /// An error that is neither the cap nor a validation issue.
    public var lastError: GTDError?

    /// The tier the note is in now, when the card is over an **existing** action (a drop onto
    /// a sidebar section). `nil` for a capture or a list item, which are new to every tier.
    /// `RequiredField.missing` asks less of a note that already is an action (R-3: "a note
    /// already in its tier is never judged again"), and the card must ask exactly what the
    /// reducer would, or its asterisks lie.
    public var previousStatus: ActionStatus?

    /// A filing waiting for a free Next slot (the cap's forced choice).
    public struct PendingFiling: Sendable, Equatable {
        public var status: ActionStatus
        public var waiting: WaitingInfo?

        public init(status: ActionStatus, waiting: WaitingInfo? = nil) {
            self.status = status
            self.waiting = waiting
        }
    }

    public init(draft: InboxDraft = InboxDraft(), previousStatus: ActionStatus? = nil) {
        self.draft = draft
        self.flagged = []
        self.shakeTrigger = 0
        self.focusRequest = nil
        self.isFieldFocused = false
        self.capCandidates = []
        self.pending = nil
        self.lastError = nil
        self.previousStatus = previousStatus
    }

    // MARK: Validation flags

    /// The fields the card must mark with an asterisk right now (STYLEGUIDE §3.6), in
    /// `RequiredField` order. A flagged field that the user has since filled drops out by
    /// itself — the mark follows the draft, not the history of refusals.
    public var missingFields: [RequiredField] {
        RequiredField.allCases.filter { flagged.contains($0) && stillMissing($0) }
    }

    /// Whether this one field's label wears the asterisk.
    public func isMissing(_ field: RequiredField) -> Bool {
        flagged.contains(field) && stillMissing(field)
    }

    private func stillMissing(_ field: RequiredField) -> Bool {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch field {
        case .why: return blank(draft.why)
        case .what: return blank(draft.what)
        case .context: return draft.contexts.allSatisfy(blank)
        case .timeEstimate: return (draft.timeBucket?.minutes ?? 0) <= 0
        // The follow-up date lives in the Waiting sheet, not on the card, so nothing on the card
        // can fill it: it stays marked until the card leaves or another refusal replaces the set.
        case .followUpDate: return true
        }
    }

    /// R-3 — what a filing into `status` is still missing, without sending anything. The reducer
    /// is the authority (`GTDError.missingFields`); this only saves the round trip.
    public func preValidate(status: ActionStatus, waiting: WaitingInfo? = nil) -> [RequiredField] {
        RequiredField.missing(
            status: status,
            previous: previousStatus,
            why: draft.why,
            what: draft.what,
            contexts: draft.contexts,
            timeEstimate: draft.timeBucket?.minutes,
            followUpDate: waiting?.followUp)
    }

    /// Marks `fields`, bumps the shake and asks for the first missing text field. The set is
    /// **replaced**, so a second refusal never leaves a stale asterisk behind.
    public mutating func flag(_ fields: [RequiredField]) {
        flagged = Set(fields)
        shakeTrigger += 1
        focusRequest = fields.first { $0 == .why } ?? fields.first { $0 == .what }
    }

    /// Clears every mark — the card left, or a fresh one arrived.
    public mutating func clearFlags() {
        flagged = []
        focusRequest = nil
    }

    /// The card has taken the focus request; it is not asked for again.
    public mutating func clearFocusRequest() {
        focusRequest = nil
    }

    mutating func clearCap() {
        capCandidates = []
        pending = nil
    }
}

// MARK: - Filing

/// The one implementation of "send this card and map every refusal onto the card's state".
/// `InboxSession` and `MakeActionModel` differ only in the command they send, which is the
/// closure — everything else (pre-validation, the cap's forced choice, the reducer's authority
/// over required fields) is here.
@MainActor
public enum ActionCardEngine {

    /// The result of one attempt. `.filed` carries what was sent, so the caller can record it.
    public enum Outcome: Sendable, Equatable {
        case filed(ActionDraft)
        case refused(InboxRefusal)
    }

    /// Pre-validates, sends, and folds every refusal back into a new state. Returns the state
    /// rather than taking it `inout`, because a stored property may not be held `inout` across
    /// an `await`.
    public static func file(
        state: ActionCardState,
        status: ActionStatus,
        waiting: WaitingInfo? = nil,
        model: AppModel,
        send: (ActionDraft) async throws -> Void
    ) async -> (state: ActionCardState, outcome: Outcome) {
        var state = state
        state.lastError = nil

        let missing = state.preValidate(status: status, waiting: waiting)
        if !missing.isEmpty {
            state.flag(missing)
            return (state, .refused(.missing(missing)))
        }

        let payload = state.draft.actionDraft(status: status, waiting: waiting)
        do {
            try await send(payload)
            state.clearFlags()
            state.clearCap()
            return (state, .filed(payload))
        } catch let error as GTDError {
            switch error {
            case let .nextCapReached(cap):
                // Forced choice, never automatic (ARCHITECTURE §6): the card springs back and the
                // sheet lists the current Next items to demote — or the user cancels. There is no
                // "send to Someday instead" shortcut (STYLEGUIDE §3.6, D14).
                state.pending = ActionCardState.PendingFiling(status: status, waiting: waiting)
                state.capCandidates = Rules.nextList(model.snapshot, today: model.today())
                return (state, .refused(.capReached(cap: cap)))
            case let .missingFields(fields):
                // R-3 — the reducer is the authority; the card marks what it named.
                state.flag(fields)
                return (state, .refused(.missing(fields)))
            default:
                state.lastError = error
                return (state, .refused(.failed(error)))
            }
        } catch {
            let wrapped = GTDError.invalid("\(error)")
            state.lastError = wrapped
            return (state, .refused(.failed(wrapped)))
        }
    }

    /// The cap's forced choice: demote one Next item, then retry what was refused. A refusal of
    /// the demotion itself leaves the pending filing where it was, so the sheet stays usable.
    public static func demoteAndRetry(
        state: ActionCardState,
        demoting id: NoteID,
        model: AppModel,
        send: (ActionDraft) async throws -> Void
    ) async -> (state: ActionCardState, outcome: Outcome)? {
        guard let pending = state.pending else { return nil }
        var state = state
        do {
            try await model.send(.setStatus(id, .someday, waiting: nil))
        } catch let error as GTDError {
            state.lastError = error
            return (state, .refused(.failed(error)))
        } catch {
            let wrapped = GTDError.invalid("\(error)")
            state.lastError = wrapped
            return (state, .refused(.failed(wrapped)))
        }
        state.clearCap()
        return await file(
            state: state, status: pending.status, waiting: pending.waiting,
            model: model, send: send)
    }
}
