import Foundation
import Observation
import GTDModel
import GTDAppCore

/// One editable field of an action. The set of fields the user has touched since the last
/// successful save is what an autosave writes — nothing else (see `ActionEditModel`).
public enum ActionField: String, Hashable, Sendable, CaseIterable {
    case title
    case why
    case what
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
///    save that included the title, the model re-points itself at the new id and calls
///    `onRename`, so the detail column and the navigation follow instead of showing
///    "action is gone".
///
/// No SwiftUI: the clock and the debounce are injected, so all of this is tested on Linux.
@MainActor
@Observable
public final class ActionEditModel {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// The note being edited. Changes when a rename lands.
    public private(set) var id: NoteID
    /// What the editor shows. `nil` once the action is gone from the vault.
    public private(set) var draft: Action?
    /// Fields edited since the last successful save.
    public private(set) var dirty: Set<ActionField> = []
    /// A refused command (cap, waiting info, title collision). The view renders it inline.
    public private(set) var lastError: (any Error)?
    public private(set) var isSaving = false
    /// True when the action disappeared from the snapshot (completed, trashed, renamed away).
    public private(set) var isMissing = false

    /// Called after a rename landed, with the new `NoteID`.
    public var onRename: ((NoteID) -> Void)?

    private let model: AppModel
    private let debounce: Duration
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
        debounce: Duration = .milliseconds(600),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.model = model
        self.id = id
        self.debounce = debounce
        self.sleep = sleep
        refresh()
    }

    // MARK: - Reading

    public var title: String { draft?.title ?? "" }
    public var why: String { draft?.why ?? "" }
    public var what: String { draft?.what ?? "" }
    public var status: ActionStatus { draft?.status ?? .backlog }
    public var contexts: [String] { draft?.contexts ?? [] }
    public var timeBucket: TimeBucket? { draft?.timeBucket }
    public var project: NoteID? { draft?.project }
    public var deferDate: Day? { draft?.deferDate }
    public var due: Day? { draft?.due }
    public var waiting: WaitingInfo? { draft?.waiting }

    /// A2 — the inline "Turn into project" button appears at two checkboxes.
    public var suggestsProject: Bool { draft.map(Rules.suggestsProject) ?? false }

    public var hasUnsavedEdits: Bool { !dirty.isEmpty }

    // MARK: - Editing

    public func setTitle(_ value: String) { edit(.title) { $0.title = value } }
    public func setWhy(_ value: String) { edit(.why) { $0.why = value } }
    public func setWhat(_ value: String) { edit(.what) { $0.what = value } }

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
                do {
                    try await self.sleep(self.debounce)
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
        guard !dirty.isEmpty, !retryBlocked else { return }
        guard let draft else { return }
        guard let base = model.snapshot.action(id) else {
            isMissing = true
            return
        }

        let saving = dirty
        let stamp = generation
        let payload = ActionEditModel.apply(saving, from: draft, onto: base)

        isSaving = true
        do {
            try await model.send(.updateAction(payload))
            isSaving = false
            lastError = nil
            // Only fields that were not touched again while the save was in flight are clean.
            for field in saving where (lastEdit[field] ?? 0) <= stamp {
                dirty.remove(field)
            }
            if saving.contains(.title) {
                followRename(to: payload.title)
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
            case .why: out.why = local.why
            case .what: out.what = local.what
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
