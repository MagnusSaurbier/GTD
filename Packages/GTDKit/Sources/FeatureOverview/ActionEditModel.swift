import Foundation
import Observation
import GTDModel
import GTDAppCore

/// One editable field of an action. The set of fields the user has touched since the last
/// successful save is what an autosave writes — nothing else (see `ActionEditModel`).
public enum ActionField: String, Hashable, Sendable, CaseIterable {
    case title
    /// The whole note body — one field, edited as one markdown document (2026-09-24).
    case body
    case status
    case contexts
    case timeEstimate
    case project
    case deferDate
    case due
    /// `waitingFor` + `followUpDate` move together (W1).
    case waiting
}

/// The editing brain behind `ActionDetailView`: a local draft, a debounced autosave and the two
/// things that make autosave dangerous here.
///
/// 1. **A snapshot arriving mid-edit must not clobber the edit, and the edit must not clobber
///    the snapshot.** The draft holds the remote action with only the *dirty* fields overlaid,
///    and a save writes only the dirty fields onto the *current* remote action. So a remote
///    change to a field the user is not editing survives the save, and the user's in-flight text
///    survives the refresh.
/// 2. **A rename changes the `NoteID`** — the reducer moves `Actions/<Title>.md` (A1). After a
///    save that included the title, the model re-points itself at the new id (and calls
///    `onRename`, an optional hook). The *navigation* follows on its own: the reducer publishes
///    the rename with the snapshot and the shell remaps its ids before pruning
///    (`GTDAppCore.NavigationRemap`), so nobody lands on "action is gone".
///
/// No SwiftUI: the clock and the debounce are injected, so all of this is tested on Linux.
@MainActor
@Observable
public final class ActionEditModel: AppModel.HeldEdits {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// The note being edited. Changes when a rename lands.
    public private(set) var id: NoteID
    /// What the editor shows. `nil` once the action is gone from the vault.
    public private(set) var draft: Action? { didSet { model.heldEditsChanged() } }
    /// Fields edited since the last successful save.
    public private(set) var dirty: Set<ActionField> = [] {
        didSet {
            if dirty.isEmpty { unsavedSince = nil } else if unsavedSince == nil { unsavedSince = Date() }
            model.heldEditsChanged()
        }
    }
    /// When the fields in `dirty` started to differ from the vault — the journal entry's time.
    private var unsavedSince: Date?
    /// A refused command (cap, waiting info, title collision). The view renders it inline.
    public private(set) var lastError: (any Error)?
    public private(set) var isSaving = false
    /// True when the action disappeared from the snapshot (completed, trashed, renamed away).
    public private(set) var isMissing = false

    /// True while the title field has the keyboard. A title save is a file move (A1) and hands
    /// the shell a new `NoteID`; doing that on every typing pause renames the note once per
    /// pause and, on iPhone, rebuilds the pushed detail under the person's fingers. So the
    /// title waits for blur, Return, `flush()` or closing; every other field autosaves as ever.
    public private(set) var isTitleHeld = false

    /// Called after a rename landed, with the new `NoteID`.
    public var onRename: ((NoteID) -> Void)?

    private let model: AppModel
    /// `nil` in the app: typed text is **held** until the field blurs, the editor closes or the
    /// app leaves the foreground (`flush()`), so typing never writes to the vault — the vault is
    /// written when the person does something, not when a timer fires. Tests pass a duration.
    private let debounce: Duration?
    private let sleep: Sleep
    private var pending: Task<Void, Never>?
    /// Monotonic edit counter — tells an in-flight save whether a field was touched again
    /// while it was awaiting the backend.
    private var generation = 0
    private var lastEdit: [ActionField: Int] = [:]
    /// Set after a refused save so the debounce does not retry the same rejected write forever.
    /// Cleared by the next edit or by an explicit `flush()`.
    private var retryBlocked = false
    /// An edit that arrived while a save was in flight; saved as soon as that one returns.
    private var saveRequested = false

    public init(
        model: AppModel,
        id: NoteID,
        debounce: Duration? = nil,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.model = model
        self.id = id
        self.debounce = debounce
        self.sleep = sleep
        model.register(self)
        refresh()
    }

    // MARK: - Reading

    public var title: String { draft?.title ?? "" }
    /// What the body editor shows: the note's whole body, with the `# Why?` / `# What?`
    /// headings added where an action note lacks them (A1). Nothing is written by looking —
    /// the added headings reach the vault with the person's first edit of the body.
    public var body: String { ActionEditModel.displayBody(draft?.body ?? "") }
    public var status: ActionStatus { draft?.status ?? .someday }
    public var contexts: [String] { draft?.contexts ?? [] }
    public var timeBucket: TimeBucket? { draft?.timeBucket }
    public var project: NoteID? { draft?.project }
    public var deferDate: Day? { draft?.deferDate }
    public var due: Day? { draft?.due }
    public var waiting: WaitingInfo? { draft?.waiting }

    /// A2 — the inline "Turn into project" button appears at two checkboxes.
    public var suggestsProject: Bool { draft.map(Rules.suggestsProject) ?? false }

    public var hasUnsavedEdits: Bool { !dirty.isEmpty }

    /// The note is gone from every list: completed (A5), trashed into `GTD/Trash/` (I4c, in
    /// which case it has left the snapshot altogether), or carrying the legacy `trash` status
    /// (R-1). The detail stops offering it for editing; an undo brings it back through `refresh()`.
    public var isClosed: Bool {
        guard let draft else { return model.snapshot.action(id) == nil }
        return draft.status.isClosed
    }

    /// The typed title and body not yet in the vault, for the crash journal (#56).
    /// Only those two: every other field is a click, and is saved at once.
    public var unsavedText: UnsavedText? {
        guard let draft, let since = unsavedSince else { return nil }
        let title = dirty.contains(.title) ? draft.title : nil
        let text = dirty.contains(.body) ? draft.body : nil
        guard title != nil || text != nil else { return nil }
        return UnsavedText(kind: .action, path: id.path, title: title, text: text, savedAt: since)
    }

    // MARK: - Editing

    /// The title is one line (A1: it is the file name) even though the field wraps (P2). Returns
    /// `true` when the input carried a Return — the view's cue to give up focus, because a
    /// wrapping text field has no submit of its own.
    @discardableResult
    public func setTitle(_ value: String) -> Bool {
        let input = ActionEditModel.titleInput(value)
        if input.text != title { edit(.title) { $0.title = input.text } }
        return input.submitted
    }

    /// Folds typed or pasted line breaks out of a title: a Return submits, pasted lines join
    /// with one space. Text without a line break passes through untouched (no trimming while
    /// the person is still typing).
    static func titleInput(_ raw: String) -> (text: String, submitted: Bool) {
        guard raw.contains(where: \.isNewline) else { return (raw, false) }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (lines.joined(separator: " "), true)
    }
    /// The body as typed. Unchanged text (the editor echoing `body` back) is not an edit.
    public func setBody(_ value: String) {
        guard value != body else { return }
        edit(.body) { $0.body = value }
    }

    /// An action note always shows its two sections (A1); `NoteBody` puts a headingless body's
    /// text under `# What?`, where the codec has always read it.
    static func displayBody(_ body: String) -> String {
        NoteBody.ensuringSections(NoteBody.actionSections, in: body)
    }

    public func setContexts(_ value: [String]) { edit(.contexts, immediate: true) { $0.contexts = value } }

    public func setTimeEstimate(_ minutes: Int?) {
        edit(.timeEstimate, immediate: true) { $0.timeEstimate = minutes }
    }

    public func setProject(_ value: NoteID?) { edit(.project, immediate: true) { $0.project = value } }
    public func setDeferDate(_ value: Day?) { edit(.deferDate, immediate: true) { $0.deferDate = value } }
    public func setDue(_ value: Day?) { edit(.due, immediate: true) { $0.due = value } }

    /// Status changes other than `waiting` (W1 needs who + follow-up, see `setWaiting`).
    public func setStatus(_ value: ActionStatus) {
        edit(.status, immediate: true) { action in
            action.status = value
            if value != .waiting {
                action.waitingFor = nil
                action.followUpDate = nil
            }
        }
    }

    /// W1 — `waiting` is only ever set together with who and a follow-up date.
    public func setWaiting(_ info: WaitingInfo) {
        editMany([.status, .waiting], immediate: true) { action in
            action.status = .waiting
            action.waitingFor = info.who
            action.followUpDate = info.followUp
        }
    }

    public func clearError() { lastError = nil }

    /// The view reports whether the title field is focused (see `isTitleHeld`). Letting go
    /// writes a pending title at once.
    public func setTitleHeld(_ held: Bool) {
        guard held != isTitleHeld else { return }
        isTitleHeld = held
        if !held, dirty.contains(.title) { schedule(immediate: true) }
    }

    // MARK: - Closing the action

    /// Tick-off from the detail (N6 undo covers it). Pending edits are written first, so the
    /// completed note carries them; a refused edit keeps the action open with its error shown.
    @discardableResult
    public func complete() async -> Bool {
        await close { .complete($0) }
    }

    /// I4c — moves the note to `GTD/Trash/`. Trash is not a status and the file is never
    /// deleted (CLAUDE.md rule 2), so undo brings the note back where it was.
    @discardableResult
    public func trash() async -> Bool {
        await close { .trashAction($0) }
    }

    private func close(_ command: (NoteID) -> GTDCommand) async -> Bool {
        await flush()
        guard lastError == nil, dirty.isEmpty, model.snapshot.action(id) != nil else { return false }
        do {
            try await model.send(command(id))      // `id` read after the flush: a rename moved it
            refresh()
            return true
        } catch {
            lastError = error
            return false
        }
    }

    // MARK: - Snapshot handling

    /// Adopts the current snapshot: every field the user has **not** touched takes the vault's
    /// value, the dirty ones keep the user's. Call it whenever `AppModel.snapshot` changes.
    public func refresh() {
        guard let remote = model.snapshot.action(id) else {
            if dirty.isEmpty {
                draft = nil
                isMissing = true
            }
            return
        }
        isMissing = false
        let local = draft ?? remote
        draft = ActionEditModel.apply(dirty, from: local, onto: remote)
    }

    // MARK: - Saving

    /// Writes the pending edits now (field blur, closing the detail column, window closing).
    public func flush() async {
        pending?.cancel()
        pending = nil
        retryBlocked = false
        isTitleHeld = false
        await save()
    }

    /// Awaits the debounce and the save it triggers. Tests use it; the UI does not need it.
    public func waitForPendingSave() async {
        while let task = pending {
            pending = nil
            await task.value
        }
    }

    private func edit(
        _ field: ActionField,
        immediate: Bool = false,
        _ mutate: (inout Action) -> Void
    ) {
        editMany([field], immediate: immediate, mutate)
    }

    private func editMany(
        _ fields: Set<ActionField>,
        immediate: Bool = false,
        _ mutate: (inout Action) -> Void
    ) {
        guard var next = draft else { return }
        mutate(&next)
        draft = next
        generation += 1
        for field in fields {
            dirty.insert(field)
            lastEdit[field] = generation
        }
        retryBlocked = false
        lastError = nil
        schedule(immediate: immediate)
    }

    private func schedule(immediate: Bool) {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                guard let debounce = self.debounce else { return }   // held until `flush()`
                do {
                    try await self.sleep(debounce)
                } catch {
                    return                       // superseded by a newer edit
                }
            }
            guard !Task.isCancelled else { return }
            await self.save()
        }
    }

    private func save() async {
        guard !isSaving else {
            saveRequested = true                 // the in-flight save picks it up when it returns
            return
        }
        let saving = isTitleHeld ? dirty.subtracting([.title]) : dirty
        guard !saving.isEmpty, !retryBlocked else { return }
        guard draft != nil else { return }
        guard model.snapshot.action(id) != nil else {
            isMissing = true
            return
        }

        let stamp = generation

        isSaving = true
        do {
            // Derived at the moment the command runs, not now: another command may still be in
            // flight, and a payload built on the snapshot it is about to replace would write
            // its fields back (T40-2, `AppModel.send(deriving:)`).
            try await model.send(deriving: { [weak self] in
                guard let self, let draft = self.draft,
                      let base = self.model.snapshot.action(self.id) else { return nil }
                return .updateAction(ActionEditModel.apply(saving, from: draft, onto: base))
            })
            isSaving = false
            lastError = nil
            // Only fields that were not touched again while the save was in flight are clean.
            for field in saving where (lastEdit[field] ?? 0) <= stamp {
                dirty.remove(field)
            }
            if saving.contains(.title), let title = draft?.title {
                followRename(to: title)
            }
            refresh()
        } catch {
            isSaving = false
            lastError = error
            // Keep the user's text; stop retrying until something changes (I4/A3: a cap refusal
            // must not turn into an endless write loop).
            retryBlocked = true
        }

        if saveRequested {
            saveRequested = false
            await save()                         // terminates: `dirty` is empty or `retryBlocked`
        }
    }

    /// A title change moves the file (A1), so the id the view was opened with is stale.
    private func followRename(to title: String) {
        let wanted = model.snapshot.config.layout.actionPath(title: title)
        if wanted == id { return }
        if model.snapshot.action(wanted) != nil {
            adopt(wanted)
        } else if model.snapshot.action(id) == nil,
                  let moved = model.snapshot.actions.first(where: { $0.title == title }) {
            // The reducer resolved a collision to another name — follow it anyway.
            adopt(moved.id)
        }
    }

    private func adopt(_ newID: NoteID) {
        id = newID
        isMissing = false
        onRename?(newID)
    }

    /// Overlays exactly `fields` of `local` onto `base`. `base` keeps its identity, so the
    /// command always addresses the note as the vault currently knows it.
    static func apply(_ fields: Set<ActionField>, from local: Action, onto base: Action) -> Action {
        var out = base
        for field in fields {
            switch field {
            case .title: out.title = local.title
            case .body: out.body = local.body
            case .status: out.status = local.status
            case .contexts: out.contexts = local.contexts
            case .timeEstimate: out.timeEstimate = local.timeEstimate
            case .project: out.project = local.project
            case .deferDate: out.deferDate = local.deferDate
            case .due: out.due = local.due
            case .waiting:
                out.waitingFor = local.waitingFor
                out.followUpDate = local.followUpDate
            }
        }
        return out
    }
}
