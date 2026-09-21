import Foundation
import Observation
import GTDModel
import GTDAppCore

/// One editable field of a list item (mirrors `FeatureOverview.ActionField`, reduced to the two
/// fields a list item actually carries — L1: no Why?/What?, no context, no status).
public enum ListItemField: Hashable, Sendable, CaseIterable {
    case title
    case notes
}

/// The editing brain behind the list item editor (title + notes, autosaving). Same two traps
/// `FeatureOverview.ActionEditModel` documents, on the smaller `ListItem` shape:
///
/// 1. **A snapshot arriving mid-edit must not clobber the edit, and the edit must not clobber the
///    snapshot.** Only the dirty field(s) are overlaid onto the current remote item and written
///    back through `AppModel.send(deriving:)`, built at the moment the command's turn comes
///    (ARCHITECTURE §4 "Command order") — not earlier, or it would put an in-flight command's
///    fields back.
/// 2. **A title change renames the file** (`updateListItem`'s title is the file name stem, like
///    an action's). After a save that included the title, the model re-points itself at the new
///    `NoteID`; the *navigation* follows on its own through `GTDAppCore.NavigationRemap`, the same
///    way a renamed action's does.
///
/// No SwiftUI: the clock and the debounce are injected, so this is tested on Linux.
@MainActor
@Observable
public final class ListItemEditModel: AppModel.HeldEdits {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// The note being edited. Changes when a rename lands.
    public private(set) var id: NoteID
    /// What the editor shows. `nil` once the item is gone from the vault.
    public private(set) var draft: ListItem?
    public private(set) var dirty: Set<ListItemField> = []
    public private(set) var lastError: (any Error)?
    public private(set) var isSaving = false
    /// True when the item disappeared from the snapshot (completed, trashed, promoted, renamed
    /// away with nothing found under the new name).
    public private(set) var isMissing = false

    /// True while the title field has the keyboard — the title save waits for blur/Return/flush,
    /// exactly as `ActionEditModel.isTitleHeld` (a title save is a file move).
    public private(set) var isTitleHeld = false

    private let model: AppModel
    /// `nil` in the app: typed text is **held** until the field blurs, the editor closes or the
    /// app leaves the foreground (`flush()`), so typing never writes to the vault — the vault is
    /// written when the person does something, not when a timer fires. Tests pass a duration.
    private let debounce: Duration?
    private let sleep: Sleep
    private var pending: Task<Void, Never>?
    private var generation = 0
    private var lastEdit: [ListItemField: Int] = [:]
    private var retryBlocked = false
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
    public var notes: String { draft?.notes ?? "" }
    public var list: String? { draft?.list }
    public var isFinished: Bool { draft?.isFinished ?? false }
    public var hasUnsavedEdits: Bool { !dirty.isEmpty }

    // MARK: - Editing

    /// One line, like `ActionEditModel.setTitle` — a wrapping field has no submit of its own, so
    /// a typed/pasted line break folds out and the return value tells the view to give up focus.
    @discardableResult
    public func setTitle(_ value: String) -> Bool {
        let input = ListItemEditModel.titleInput(value)
        if input.text != title { edit(.title) { $0.title = input.text } }
        return input.submitted
    }

    static func titleInput(_ raw: String) -> (text: String, submitted: Bool) {
        guard raw.contains(where: \.isNewline) else { return (raw, false) }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (lines.joined(separator: " "), true)
    }

    public func setNotes(_ value: String) { edit(.notes) { $0.notes = value } }

    public func clearError() { lastError = nil }

    public func setTitleHeld(_ held: Bool) {
        guard held != isTitleHeld else { return }
        isTitleHeld = held
        if !held, dirty.contains(.title) { schedule(immediate: true) }
    }

    // MARK: - Closing the item

    /// L3 — moves the note to `Lists/<name>/Done/`. Pending edits are written first.
    @discardableResult
    public func complete() async -> Bool {
        await close { .completeListItem($0) }
    }

    /// I4c — moves the note to `GTD/Trash/`. Never a hard delete, so undo brings it back.
    @discardableResult
    public func trash() async -> Bool {
        await close { .trashListItem($0) }
    }

    private func close(_ command: (NoteID) -> GTDCommand) async -> Bool {
        await flush()
        guard lastError == nil, dirty.isEmpty, model.snapshot.listItem(id) != nil else { return false }
        do {
            try await model.send(command(id))
            refresh()
            return true
        } catch {
            lastError = error
            return false
        }
    }

    // MARK: - Snapshot handling

    /// Adopts the current snapshot: an untouched field takes the vault's value, a dirty one keeps
    /// the user's. Call it whenever `AppModel.snapshot` changes.
    public func refresh() {
        guard let remote = model.snapshot.listItem(id) else {
            if dirty.isEmpty {
                draft = nil
                isMissing = true
            }
            return
        }
        isMissing = false
        let local = draft ?? remote
        draft = ListItemEditModel.apply(dirty, from: local, onto: remote)
    }

    // MARK: - Saving

    public func flush() async {
        pending?.cancel()
        pending = nil
        retryBlocked = false
        isTitleHeld = false
        await save()
    }

    public func waitForPendingSave() async {
        while let task = pending {
            pending = nil
            await task.value
        }
    }

    private func edit(_ field: ListItemField, _ mutate: (inout ListItem) -> Void) {
        guard var next = draft else { return }
        mutate(&next)
        draft = next
        generation += 1
        dirty.insert(field)
        lastEdit[field] = generation
        retryBlocked = false
        lastError = nil
        schedule(immediate: false)
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
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self.save()
        }
    }

    private func save() async {
        guard !isSaving else {
            saveRequested = true
            return
        }
        let saving = isTitleHeld ? dirty.subtracting([.title]) : dirty
        guard !saving.isEmpty, !retryBlocked else { return }
        guard draft != nil else { return }
        guard model.snapshot.listItem(id) != nil else {
            isMissing = true
            return
        }

        let stamp = generation

        isSaving = true
        do {
            // Built when the command's turn comes, not now — ARCHITECTURE §4 "Command order".
            try await model.send(deriving: { [weak self] in
                guard let self, let draft = self.draft,
                      let base = self.model.snapshot.listItem(self.id) else { return nil }
                let merged = ListItemEditModel.apply(saving, from: draft, onto: base)
                return .updateListItem(self.id, title: merged.title, notes: merged.notes)
            })
            isSaving = false
            lastError = nil
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
            retryBlocked = true
        }

        if saveRequested {
            saveRequested = false
            await save()
        }
    }

    /// A title change moves the file, so the id the view was opened with may be stale.
    private func followRename(to title: String) {
        guard let list else { return }
        let wanted = model.snapshot.config.layout.listItemPath(
            list: list, title: title, finished: isFinished)
        if wanted == id { return }
        if model.snapshot.listItem(wanted) != nil {
            adopt(wanted)
        } else if model.snapshot.listItem(id) == nil,
                  let moved = model.snapshot.listItems.first(where: {
                      $0.title == title && GTDList.sameName($0.list, list)
                  }) {
            adopt(moved.id)
        }
    }

    private func adopt(_ newID: NoteID) {
        id = newID
        isMissing = false
    }

    /// Overlays exactly `fields` of `local` onto `base`.
    static func apply(_ fields: Set<ListItemField>, from local: ListItem, onto base: ListItem) -> ListItem {
        var out = base
        for field in fields {
            switch field {
            case .title: out.title = local.title
            case .notes: out.notes = local.notes
            }
        }
        return out
    }
}
