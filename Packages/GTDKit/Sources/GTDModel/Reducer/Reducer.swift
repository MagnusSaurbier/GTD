import Foundation

/// The single place where GTD semantics live: cap enforcement, waiting validation, completion,
/// promotion, demotion, archive eligibility. UI and backends never re-implement any of it.
///
/// `reduce` is a pure function of `(snapshot, command, env)`: no clock, no file system, no
/// randomness. Same input ⇒ equal `Reduction`.
///
/// ### How `extraOps` relates to the snapshot diff
/// `GTDServices` turns `Reduction` into file operations: it diffs old vs. new snapshot and
/// encodes changed entities. `extraOps` covers file effects the diff cannot express.
/// One rule makes the two agree: **a path mentioned in `extraOps` is owned by `extraOps`** — the
/// diff must not also emit an operation for it. That is why every command that makes a note
/// leave its collection (inbox filing, archiving, renaming, converting) emits the move itself.
/// `.delete` means "move to `GTD/Trash/`" — the app never hard-deletes (ARCHITECTURE §3).
///
/// ### The rules this file enforces
/// | Rule | Where |
/// | --- | --- |
/// | I4/A3 Next cap (`in-progress` counts) | `checkCap` |
/// | I5 defer to review needs a reason | `deferInboxToReview` |
/// | A1 one file per action, unique title | `makeAction`, `updateAction` |
/// | A4 contexts are a closed list | `normalizeContexts` |
/// | A5 done sets a closing date, archive after 30 d | `normalize`, `archiveCompleted` |
/// | I4c trash is a move, never a status | `trashAction`, `fileInbox` |
/// | W1/D39 waiting needs a follow-up date (who is optional); leaving clears both | `normalize` |
/// | I4/D12/R-3 a new transition into a tier brings that tier's required fields | `normalize` |
/// | C3/R-4 an inbox note's title is its file name; renaming it is a move; filing keeps it | `renameInboxItem`, `fileInbox` |
/// | R-4 a body that is only the Why/What template skeleton is carried over as empty | `fileInbox`, `CaptureText.isEmptyBody` |
/// | I4a/R-8 the project chip, including the project it creates | `makeAction`, `resolveProject` |
/// | R-2 a Next item may be deferred; it just does not occupy a slot while hidden | `Rules` |
/// | P3 only active projects put actions into Next; leaving `active` demotes | `normalize`, `updateProject` |
/// | P4/P5 completion logs, ticks the step and asks "what's next?" | `settle` |
/// | R5 one routine-log entry per step per day per device | `logRoutineStep` |
public enum Reducer {

    public static func reduce(
        _ s: VaultSnapshot,
        _ c: GTDCommand,
        env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        var reduction = try reduceCommand(s, c, env: env)
        linkProjectSteps(from: s, into: &reduction)
        return reduction
    }

    /// #76 — every action in a project is a step of that project's note. Whatever command put
    /// an action into a project (a new action, a filed capture, a list item, a changed project
    /// chip) leaves a `- [ ] Title → [[Action]]` line behind in that project, unless a step
    /// already points at it (`promoteStep`, `linkStep`). An action that moves to another
    /// project takes its open step along; a ticked step stays behind as history. Actions that
    /// were already in a project before this command are left as they are — no command writes
    /// into a project note it had nothing to do with.
    private static func linkProjectSteps(from old: VaultSnapshot, into reduction: inout Reduction) {
        var next = reduction.snapshot
        let backwards = reduction.renames.inverted
        for action in next.actions {
            let before = old.action(backwards.resolve(action.id))
            let oldProject = before?.project.map { reduction.renames.resolve($0) }
            guard action.project != oldProject else { continue }

            if let oldProject, let index = next.projects.firstIndex(where: { $0.id == oldProject }) {
                next.projects[index].steps.removeAll { $0.promotedTo == action.id && !$0.done }
            }
            guard let projectID = action.project,
                  let index = next.projects.firstIndex(where: { $0.id == projectID }),
                  !next.projects[index].steps.contains(where: { $0.promotedTo == action.id })
            else { continue }
            next.projects[index].steps.append(ProjectStep(
                text: action.title, done: action.status == .done, promotedTo: action.id))
        }
        reduction.snapshot = next
    }

    private static func reduceCommand(
        _ s: VaultSnapshot,
        _ c: GTDCommand,
        env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        switch c {
        case let .renameInboxItem(id, title):
            return try renameInboxItem(s, id: id, title: title)

        case let .editInboxBody(id, body):
            return try editInboxBody(s, id: id, body: body)

        case let .fileInbox(id, decision):
            return try fileInbox(s, id: id, decision: decision, env: env)

        case let .deferInboxToReview(id, reason):
            return try deferInboxToReview(s, id: id, reason: reason)

        case let .createAction(draft):
            return try createAction(s, draft: draft, env: env)

        case let .updateAction(action):
            return try updateAction(s, action: action, env: env)

        case let .setStatus(id, status, waiting):
            return try setStatus(s, id: id, status: status, waiting: waiting, env: env)

        case let .trashAction(id):
            return try trashAction(s, id: id)

        case let .complete(id):
            return try complete(s, id: id, env: env)

        case let .toggleCheckbox(id, index):
            return try toggleCheckbox(s, id: id, index: index, env: env)

        case let .convertActionToProject(id, draft):
            return try convertActionToProject(s, id: id, draft: draft, env: env)

        case let .createArea(title):
            var next = s
            _ = try addArea(title: title, to: &next, reusingExisting: false)
            return Reduction(snapshot: next)

        case let .createProject(draft):
            var next = s
            _ = try addProject(draft, to: &next)
            return Reduction(snapshot: next)

        case let .updateProject(project):
            return try updateProject(s, project: project, env: env)

        case let .promoteStep(projectID, stepIndex, draft):
            return try promoteStep(s, projectID: projectID, stepIndex: stepIndex, draft: draft, env: env)

        case let .linkStep(projectID, actionID):
            return try linkStep(s, projectID: projectID, actionID: actionID, env: env)

        case let .createList(name):
            return try createList(s, name: name)

        case let .renameList(from, to):
            return try renameList(s, from: from, to: to)

        case let .removeList(name):
            return try removeList(s, name: name)

        case let .setFavouriteLists(names):
            return try setFavouriteLists(s, names: names)

        case .pruneFavouriteLists:
            return pruneFavouriteLists(s)

        case let .setListIcon(list, symbol):
            return try setListIcon(s, list: list, symbol: symbol)

        case let .addListItem(list, title, notes):
            return try addListItem(s, list: list, title: title, notes: notes, env: env)

        case let .updateListItem(id, title, notes):
            return try updateListItem(s, id: id, title: title, notes: notes)

        case let .completeListItem(id):
            return try completeListItem(s, id: id)

        case let .trashListItem(id):
            return try trashListItem(s, id: id)

        case let .promoteListItem(id, draft):
            return try promoteListItem(s, id: id, draft: draft, env: env)

        case let .moveActionToList(id, list):
            return try moveActionToList(s, id: id, list: list)

        case let .saveWeeklyReview(review):
            return try saveWeeklyReview(s, review: review, env: env)

        case let .logRoutineStep(routineID, stepID, result):
            return try logRoutineStep(s, routineID: routineID, stepID: stepID, result: result, env: env)

        case let .setRoutineTime(routineID, time):
            guard let index = s.routines.firstIndex(where: { $0.id == routineID }) else {
                throw .notFound(routineID)
            }
            var next = s
            next.routines[index].time = time
            return Reduction(snapshot: next)

        case let .updateConfig(config):
            return try updateConfig(s, config: config)

        case .archiveCompleted:
            return archiveCompleted(s, env: env)
        }
    }

    // MARK: - Inbox

    /// C3/R-4 — the card's title field. The title **is** the file name, so a new title moves
    /// the file within `Inbox/`, like renaming an action. The new name is cut and sanitised like
    /// a capture's (`CaptureText.renamedTitle`); an empty one is refused and a name that is taken is a
    /// `.titleCollision` — a rename never overwrites and never picks a ` 2` behind the user's back.
    private static func renameInboxItem(
        _ s: VaultSnapshot, id: NoteID, title: String
    ) throws(GTDError) -> Reduction {
        guard let index = s.inbox.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        guard let clean = CaptureText.renamedTitle(title) else { throw .invalid(Message.titleRequired) }
        let target = s.config.layout.inboxPath(title: clean)
        guard target != id else { return Reduction(snapshot: s) }
        guard !pathExists(target, in: s) else { throw .titleCollision(clean) }
        let item = s.inbox[index]
        var next = s
        next.inbox[index] = InboxItem(
            id: target, body: item.body, created: item.created,
            reviewReason: item.reviewReason, passthrough: item.passthrough)
        var renames = RenameMap.empty
        renames.record(id, as: target)
        return Reduction(
            snapshot: next, extraOps: [.move(from: id.path, to: target.path)], renames: renames)
    }

    /// The body of an inbox note — everything below its frontmatter. Separate from the title,
    /// which lives in the file name (`renameInboxItem`).
    private static func editInboxBody(
        _ s: VaultSnapshot, id: NoteID, body: String
    ) throws(GTDError) -> Reduction {
        guard let index = s.inbox.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var next = s
        next.inbox[index].body = body
        return Reduction(snapshot: next)
    }

    /// I5 — the escape hatch. The app asks *why* the item does not fit; the reason travels into
    /// the weekly review so the gap can be fixed. Such items leave the processing queue.
    private static func deferInboxToReview(
        _ s: VaultSnapshot, id: NoteID, reason: String
    ) throws(GTDError) -> Reduction {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalid(Message.reviewReasonRequired) }
        guard let index = s.inbox.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var next = s
        next.inbox[index].reviewReason = trimmed
        return Reduction(snapshot: next)
    }

    /// I4 — the four destinations of a card. **The capture file never disappears:** filing an
    /// action, a Knowledge note or a list item *moves* it to where the note now belongs (so its
    /// `created` stamp and anything the user put in its frontmatter survive the filing), and
    /// Trash moves it to `GTD/Trash/` (I4c).
    ///
    /// R-4 — the filed note keeps the inbox note's **title, which is its file name** (C3). The
    /// body comes along — above `# Why?` for an action, above the notes panel for Knowledge and
    /// list items — unless it says nothing: a body that is only the empty Why/What template
    /// skeleton counts as empty (`CaptureText.isEmptyBody`), so it never ends up in the note twice.
    private static func fileInbox(
        _ s: VaultSnapshot, id: NoteID, decision: InboxDecision, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let item = s.inboxItem(id) else { throw .notFound(id) }
        var next = s
        let layout = s.config.layout
        var extraOps: [VaultFileOp] = []
        var filedNotes: [FiledNote] = []
        var renames = RenameMap.empty

        // The file name *is* the title (C3) — the card's title field renames the file
        // (`renameInboxItem`) before it is filed, so there is only one title and it is this one.
        // Sanitising is a no-op for any name a file can have; it only guards what a wikilink
        // could not carry. The name is *not* cut to 60 characters — the user chose it.
        let title = VaultLayout.sanitize(item.title)

        switch decision {
        case let .action(draft):
            var filed = draft
            filed.title = title
            filed.preamble = CaptureText.filedBody(body: item.body, notes: "")
            // I4a/R-8 — the `+ project` chip may name a project that does not exist yet;
            // `makeAction` creates it, so filing the card stays one command and one commit.
            let action = try makeAction(from: filed, in: &next, env: env, created: item.created)
            next.actions.append(action)
            extraOps.append(.move(from: item.id.path, to: action.id.path))
            renames.record(item.id, as: action.id)

        case let .knowledge(target, notes):
            let noteID = try knowledgePath(target, title: title, in: next)
            guard !pathExists(noteID, in: next) else { throw .titleCollision(title) }
            guard noteID != item.id else { throw .invalid(Message.knowledgeTargetIsSource) }
            // The capture *becomes* the knowledge note (I4): the file moves, and the notes panel
            // — with the full capture text above it when the title had to cut it — is its body.
            extraOps.append(.move(from: item.id.path, to: noteID.path))
            filedNotes.append(FiledNote(
                id: noteID,
                body: CaptureText.filedBody(body: item.body, notes: notes),
                created: item.created,
                source: item.passthrough))
            renames.record(item.id, as: noteID)

        case let .list(name, notes):
            guard let list = next.list(named: name) else { throw .invalid(Message.unknownList(name)) }
            let target = layout.listItemPath(list: list.name, title: title)
            guard !pathExists(target, in: next) else { throw .titleCollision(title) }
            guard target != item.id else { throw .invalid(Message.knowledgeTargetIsSource) }
            // The capture *becomes* the list item — the file moves rather than being re-created,
            // so its `created` timestamp and anything the user put in the frontmatter survive.
            next.listItems.append(ListItem(
                id: target,
                list: list.name,
                title: title,
                isFinished: false,
                created: item.created,
                notes: CaptureText.filedBody(body: item.body, notes: notes),
                passthrough: item.passthrough))
            extraOps.append(.move(from: item.id.path, to: target.path))
            renames.record(item.id, as: target)

        case .trash:
            extraOps.append(.delete(path: item.id.path))
        }

        next.inbox.removeAll { $0.id == id }
        try checkCap(old: s, new: next, today: env.today)
        return Reduction(
            snapshot: next, extraOps: extraOps, filedNotes: filedNotes, renames: renames)
    }

    /// I4b/D36 — where a Knowledge filing lands: a folder under `Knowledge/`, or the folder of
    /// an **active** project (reference material for a project is filed through this branch).
    private static func knowledgePath(
        _ target: KnowledgeTarget, title: String, in s: VaultSnapshot
    ) throws(GTDError) -> NoteID {
        switch target {
        case let .folder(folder):
            return s.config.layout.knowledgePath(folder: folder, title: title)
        case let .project(projectID):
            guard let project = s.project(projectID) else { throw .notFound(projectID) }
            guard project.status == .active else { throw .invalid(Message.projectNotActive) }
            return NoteID(path: "\(project.id.folder)/\(VaultLayout.sanitize(title)).md")
        }
    }

    /// I4a/R-8 — the project an action draft names: an existing one, or one created here from
    /// `newProjectTitle` (name only, area-less — P1/D35). The **one** place a project is born
    /// from an action draft, which is why `Projects/no_area/` (R-6) lives in `addProject` alone.
    private static func resolveProject(
        for draft: ActionDraft, in s: inout VaultSnapshot
    ) throws(GTDError) -> NoteID? {
        guard let newTitle = draft.newProjectTitle,
              !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return draft.project }
        guard draft.project == nil else { throw .invalid(Message.projectChoiceAmbiguous) }
        return try addProject(ProjectDraft(title: newTitle), to: &s).id
    }

    // MARK: - Actions

    private static func createAction(
        _ s: VaultSnapshot, draft: ActionDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        var next = s
        let action = try makeAction(from: draft, in: &next, env: env)
        next.actions.append(action)
        try checkCap(old: s, new: next, today: env.today)
        return Reduction(snapshot: next)
    }

    /// Editing an action in place. A title change is a file move (A1), and any project step that
    /// pointed at the old file follows it.
    private static func updateAction(
        _ s: VaultSnapshot, action: Action, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == action.id }) else {
            throw .notFound(action.id)
        }
        let previous = s.actions[index]

        var updated = action
        updated.created = previous.created          // `created` is written once, by capture (A1)
        try normalize(&updated, previous: previous, waiting: action.waiting, in: s, env: env)

        var next = s
        var extraOps: [VaultFileOp] = []
        var renames = RenameMap.empty

        let wantedID = s.config.layout.actionPath(title: updated.title)
        if wantedID != previous.id {
            guard !pathExists(wantedID, in: s) else { throw .titleCollision(updated.title) }
            let moved = rekey(updated, to: wantedID)
            next.actions[index] = moved
            extraOps.append(.move(from: previous.id.path, to: wantedID.path))
            retarget(from: previous.id, to: wantedID, in: &next)
            // The note is not gone, it is called something else now. Saying so is what keeps a
            // pushed detail (iPhone) and the selected row (Mac) on the note being edited.
            renames.record(previous.id, as: wantedID)
        } else {
            next.actions[index] = updated
        }

        try checkCap(old: s, new: next, today: env.today)
        let prompts = settle(&next, at: index, previousStatus: previous.status, env: env)
        return Reduction(
            snapshot: next, prompts: prompts, extraOps: extraOps, renames: renames)
    }

    /// The one command every list uses to move an action between commitment tiers (A3, W1).
    private static func setStatus(
        _ s: VaultSnapshot, id: NoteID, status: ActionStatus, waiting: WaitingInfo?, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        let previous = s.actions[index]
        guard !(previous.status == .done && status == .done) else { return Reduction(snapshot: s) }

        var updated = previous
        updated.status = status
        try normalize(&updated, previous: previous, waiting: waiting, in: s, env: env)

        var next = s
        next.actions[index] = updated
        try checkCap(old: s, new: next, today: env.today)
        let prompts = settle(&next, at: index, previousStatus: previous.status, env: env)
        return Reduction(snapshot: next, prompts: prompts)
    }

    /// I4c — trash is a move, not a status. The note leaves the snapshot without an `extraOp`,
    /// which is exactly the "removed entity nobody spoke for" rule of ARCHITECTURE §4: the diff
    /// emits `.delete`, and `GTDVault` performs a `.delete` as a move into `GTD/Trash/`. So the
    /// file survives, undo restores it, and no `status: trash` is ever written.
    private static func trashAction(_ s: VaultSnapshot, id: NoteID) throws(GTDError) -> Reduction {
        guard s.action(id) != nil else { throw .notFound(id) }
        var next = s
        next.actions.removeAll { $0.id == id }
        retarget(from: id, to: nil, in: &next)
        return Reduction(snapshot: next)
    }

    /// A5/P4/P5 — completing an action. Idempotent: completing a done action changes nothing,
    /// so a double tap never writes a second log entry.
    private static func complete(
        _ s: VaultSnapshot, id: NoteID, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        let previous = s.actions[index]
        guard previous.status != .done else { return Reduction(snapshot: s) }

        var updated = previous
        updated.status = .done
        try normalize(&updated, previous: previous, waiting: nil, in: s, env: env)

        var next = s
        next.actions[index] = updated
        let prompts = settle(&next, at: index, previousStatus: previous.status, env: env)
        return Reduction(snapshot: next, prompts: prompts)
    }

    /// Everything that happens *after* an action's status has been written: the project log,
    /// the promoted step, the "What's next?" prompt (P4, P5).
    private static func settle(
        _ next: inout VaultSnapshot, at index: Int, previousStatus: ActionStatus, env: ReducerEnv
    ) -> [AppPrompt] {
        let action = next.actions[index]
        guard action.status == .done, previousStatus != .done else { return [] }
        guard let projectID = action.project,
              let projectIndex = next.projects.firstIndex(where: { $0.id == projectID })
        else { return [] }

        // P6 — the project note keeps a dated log of what got done.
        next.projects[projectIndex].log.append(LogEntry(day: env.today, text: action.title))
        // P4 — the step this action came from is now done.
        if let stepIndex = next.projects[projectIndex].steps.firstIndex(where: { $0.promotedTo == action.id }) {
            next.projects[projectIndex].steps[stepIndex].done = true
        }
        // P5 — only an active project can take a next step right now.
        guard next.projects[projectIndex].status == .active else { return [] }
        return [.whatsNext(project: projectID)]
    }

    /// Ticking one checkbox of the `# What?` body (A2). Rewrites exactly that line.
    private static func toggleCheckbox(
        _ s: VaultSnapshot, id: NoteID, index: Int, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let actionIndex = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        guard index >= 0 else { throw .invalid(Message.noCheckbox(index)) }
        var lines = s.actions[actionIndex].what.components(separatedBy: "\n")
        var seen = -1
        var toggled = false
        for lineIndex in lines.indices {
            guard !Checkbox.scan(lines[lineIndex]).isEmpty else { continue }
            seen += 1
            guard seen == index else { continue }
            lines[lineIndex] = flipMark(lines[lineIndex])
            toggled = true
            break
        }
        guard toggled else { throw .invalid(Message.noCheckbox(index)) }
        var next = s
        next.actions[actionIndex].what = lines.joined(separator: "\n")
        next.actions[actionIndex].modified = env.now
        return Reduction(snapshot: next)
    }

    private static func flipMark(_ line: String) -> String {
        if let range = line.range(of: "[ ]") { return line.replacingCharacters(in: range, with: "[x]") }
        if let range = line.range(of: "[x]") { return line.replacingCharacters(in: range, with: "[ ]") }
        if let range = line.range(of: "[X]") { return line.replacingCharacters(in: range, with: "[ ]") }
        return line
    }

    // MARK: - Projects

    /// A2 — "Turn into project". The action's checkboxes become the project's steps and its
    /// note is superseded (moved to `GTD/Trash/`); the prompt asks which step to promote first,
    /// so the new project does not start out stalled (P4, P5).
    private static func convertActionToProject(
        _ s: VaultSnapshot, id: NoteID, draft: ProjectDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let action = s.action(id) else { throw .notFound(id) }
        var next = s
        var effective = draft
        if effective.steps.isEmpty {
            effective.steps = action.checkboxes.map(\.text).filter { !$0.isEmpty }
        }
        if effective.why.isEmpty { effective.why = action.why }
        let project = try addProject(effective, to: &next)

        next.actions.removeAll { $0.id == id }
        retarget(from: id, to: nil, in: &next)
        return Reduction(
            snapshot: next,
            prompts: [.whatsNext(project: project.id)],
            extraOps: [.move(from: id.path, to: s.config.layout.trashPath(for: id).path)])
    }

    /// P3 — a project that is not `active` cannot hold actions in Next; changing its status
    /// demotes them to Someday.
    ///
    /// **Renaming** a project is still refused: the folder name is its identity and the title has
    /// to keep matching the note's path. Its **area**, however, is exactly that folder's parent,
    /// so changing it is one command and one commit (R-7, D42): the project folder moves
    /// (`VaultFileOp.moveFolder`, R-5) into the area's folder — or into `Projects/no_area/` when
    /// the area is taken away — every action linked to the project follows the note to its new
    /// path, and the project note plus every file that travelled inside the folder is reported in
    /// `renames`, so an open detail view follows the project instead of concluding it is gone.
    ///
    /// A promoted step is deliberately *not* retargeted: `ProjectStep.promotedTo` points at an
    /// action in `Actions/`, which does not move.
    private static func updateProject(
        _ s: VaultSnapshot, project: Project, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.projects.firstIndex(where: { $0.id == project.id }) else {
            throw .notFound(project.id)
        }
        let previous = s.projects[index]
        guard VaultLayout.sanitize(project.title) == previous.title else {
            throw .invalid(Message.projectRenameUnsupported)
        }
        if let areaID = project.area, s.area(areaID) == nil { throw .notFound(areaID) }

        var next = s
        var extraOps: [VaultFileOp] = []
        var renames = RenameMap.empty
        var updated = project

        // R-7 — the area *is* the folder the project folder sits in. The source is taken from
        // the note's real path rather than from `previous.area`, so a legacy project still
        // sitting directly under `Projects/` moves out of there correctly too (R-6).
        let oldFolder = previous.id.folder
        let folderName = NoteID(path: oldFolder).title
        let newFolder = "\(project.area?.folder ?? s.config.layout.noArea)/\(folderName)"
        if newFolder != oldFolder {
            guard !folderIsTaken(newFolder, in: s) else { throw .titleCollision(folderName) }
            let movedID = NoteID(path: newFolder + previous.id.path.dropFirst(oldFolder.count))
            updated = rekey(project, to: movedID, movingFrom: oldFolder, to: newFolder)
            extraOps.append(.moveFolder(from: oldFolder, to: newFolder))
            renames.record(previous.id, as: movedID)
            // Everything else inside the folder travels with it — reference files (P6) and the
            // Knowledge notes filed into a project folder (I4b). An open one must follow too.
            for path in previous.referenceFiles {
                let file = NoteID(path: path)
                guard file.isInside(oldFolder) else { continue }
                renames.record(file, as: NoteID(path: newFolder + file.path.dropFirst(oldFolder.count)))
            }
            // The `project:` wikilink of every action is written from this id, so re-pointing the
            // entity is what rewrites the line on disk — in the same commit as the folder move.
            for actionIndex in next.actions.indices
            where next.actions[actionIndex].project == previous.id {
                next.actions[actionIndex].project = movedID
            }
        }
        next.projects[index] = updated

        if updated.status != .active {
            for actionIndex in next.actions.indices
            where next.actions[actionIndex].project == updated.id
                && next.actions[actionIndex].status.countsTowardCap {
                next.actions[actionIndex].status = .someday
                next.actions[actionIndex].modified = env.now
            }
        }
        return Reduction(snapshot: next, extraOps: extraOps, renames: renames)
    }

    /// Is something already sitting on `folder`? The snapshot only knows about notes, which is
    /// enough for the refusal the user sees; `GTDVault` refuses a `.moveFolder` onto an occupied
    /// destination as well, so a folder nothing was indexed from cannot be overwritten either.
    private static func folderIsTaken(_ folder: String, in s: VaultSnapshot) -> Bool {
        let id = NoteID(path: folder)
        return s.projects.contains { $0.id.isInside(id.path) }
            || s.areas.contains { $0.id.isInside(id.path) }
            || s.actions.contains { $0.id.isInside(id.path) }
            || s.listItems.contains { $0.id.isInside(id.path) }
    }

    /// The same project under a new path, with the files inside its folder re-pointed (R-7).
    private static func rekey(
        _ project: Project, to id: NoteID, movingFrom oldFolder: String, to newFolder: String
    ) -> Project {
        Project(
            id: id,
            title: project.title,
            area: project.area,
            status: project.status,
            outcome: project.outcome,
            why: project.why,
            steps: project.steps,
            log: project.log,
            referenceFiles: project.referenceFiles.map { path in
                let file = NoteID(path: path)
                guard file.isInside(oldFolder) else { return path }
                return newFolder + file.path.dropFirst(oldFolder.count)
            },
            passthrough: project.passthrough)
    }

    /// P4 — turning a checklist line of the project note into a real action note.
    private static func promoteStep(
        _ s: VaultSnapshot, projectID: NoteID, stepIndex: Int, draft: ActionDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let projectIndex = s.projects.firstIndex(where: { $0.id == projectID }) else {
            throw .notFound(projectID)
        }
        guard s.projects[projectIndex].steps.indices.contains(stepIndex) else {
            throw .invalid(Message.noStep(stepIndex))
        }
        let step = s.projects[projectIndex].steps[stepIndex]
        guard step.promotedTo == nil else { throw .invalid(Message.stepAlreadyPromoted) }
        guard !step.done else { throw .invalid(Message.stepAlreadyDone) }

        var next = s
        var linked = draft
        linked.project = projectID
        if linked.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            linked.title = step.text      // the step's own wording is the honest default
        }
        // …and the step line *is* the next physical action, so it is the honest `What?` too.
        // Without it R-3 would refuse even a Someday promotion, and P5's one-tap promotion
        // (which asks for nothing else) could not exist.
        if linked.what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            linked.what = step.text
        }
        let action = try makeAction(from: linked, in: &next, env: env)
        next.actions.append(action)
        next.projects[projectIndex].steps[stepIndex].promotedTo = action.id
        try checkCap(old: s, new: next, today: env.today)
        return Reduction(snapshot: next)
    }

    /// P6/#61 — a new step that is already an action: the step line reads the action's title and
    /// points at it (`→ [[Action]]`), and the action's `project:` names this project. One
    /// command, so one undo takes back both halves.
    private static func linkStep(
        _ s: VaultSnapshot, projectID: NoteID, actionID: NoteID, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let projectIndex = s.projects.firstIndex(where: { $0.id == projectID }) else {
            throw .notFound(projectID)
        }
        guard let actionIndex = s.actions.firstIndex(where: { $0.id == actionID }) else {
            throw .notFound(actionID)
        }
        let previous = s.actions[actionIndex]
        guard !previous.status.isClosed else { throw .invalid(Message.linkClosedAction) }
        guard previous.project == nil || previous.project == projectID else {
            throw .invalid(Message.actionInOtherProject)
        }
        guard !s.projects[projectIndex].steps.contains(where: { $0.promotedTo == actionID }) else {
            throw .invalid(Message.actionAlreadyAStep)
        }

        var next = s
        var linked = previous
        linked.project = projectID
        // Same checks as any edit of the action — e.g. a Next action cannot join an on-hold project.
        try normalize(&linked, previous: previous, waiting: previous.waiting, in: s, env: env)
        next.actions[actionIndex] = linked
        next.projects[projectIndex].steps.append(ProjectStep(text: linked.title, promotedTo: actionID))
        try checkCap(old: s, new: next, today: env.today)
        return Reduction(snapshot: next)
    }

    /// P1 — an area is a folder with its own note. `reusingExisting` is true only for the
    /// "create the area while creating the project" path, where hitting an existing area is
    /// the user naming one, not a collision.
    @discardableResult
    private static func addArea(
        title: String, to s: inout VaultSnapshot, reusingExisting: Bool
    ) throws(GTDError) -> Area {
        let name = try requireTitle(title)
        // R-6 — `no_area` is the folder that holds the area-less projects. Letting an area take
        // that name would make `Projects/no_area/` mean two things at once.
        guard !VaultLayout.isNoAreaFolderName(name) else { throw .invalid(Message.areaNameReserved) }
        let id = s.config.layout.areaPath(title: name)
        if let existing = s.area(id) {
            guard reusingExisting else { throw .titleCollision(name) }
            return existing
        }
        guard !pathExists(id, in: s) else { throw .titleCollision(name) }
        let area = Area(id: id, title: name)
        s.areas.append(area)
        return area
    }

    /// P1/P2 — a new project note, optionally creating its area in the same step.
    ///
    /// R-6 — a project with no area is **not** loose under `Projects/`: `projectPath` puts it in
    /// `Projects/no_area/`. This is the one place a project is born (`createProject`, the inbox
    /// project chip of R-8, `convertActionToProject`), so that holds for all three.
    @discardableResult
    private static func addProject(_ draft: ProjectDraft, to s: inout VaultSnapshot) throws(GTDError) -> Project {
        let title = try requireTitle(draft.title)
        var areaID = draft.area
        if let newAreaTitle = draft.newAreaTitle,
           !newAreaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            areaID = try addArea(title: newAreaTitle, to: &s, reusingExisting: true).id
        }
        if let areaID, s.area(areaID) == nil { throw .notFound(areaID) }

        let id = s.config.layout.projectPath(title: title, inArea: areaID)
        guard !pathExists(id, in: s) else { throw .titleCollision(title) }
        let project = Project(
            id: id,
            title: title,
            area: areaID,
            status: .active,
            outcome: draft.outcome,
            why: draft.why,
            steps: draft.steps
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { ProjectStep(text: $0) })
        s.projects.append(project)
        return project
    }

    /// Keeps `ProjectStep.promotedTo` pointing at the right note when an action is renamed
    /// (`to:` the new id) or superseded (`to: nil`).
    private static func retarget(from old: NoteID, to new: NoteID?, in s: inout VaultSnapshot) {
        for projectIndex in s.projects.indices {
            for stepIndex in s.projects[projectIndex].steps.indices
            where s.projects[projectIndex].steps[stepIndex].promotedTo == old {
                s.projects[projectIndex].steps[stepIndex].promotedTo = new
            }
        }
    }

    // MARK: - Lists (§5a)

    /// L2 — a list is a folder, so creating one creates `Lists/<name>/` and nothing else.
    ///
    /// Not undoable (`Rules.isUndoable`): the only inverse would be removing a directory, and
    /// nothing in this app removes anything. An empty folder left behind costs nothing.
    private static func createList(_ s: VaultSnapshot, name: String) throws(GTDError) -> Reduction {
        let clean = try requireListName(name)
        // The collision names the list that is already there, not the spelling that was asked
        // for: on a case-insensitive file system `read` and `Read` are the same folder.
        if let existing = s.list(named: clean) { throw .titleCollision(existing.name) }
        var next = s
        next.lists.append(GTDList(name: clean))
        return Reduction(
            snapshot: next,
            extraOps: [.createFolder(path: s.config.layout.listFolder(clean))])
    }

    /// L2 — renaming a list renames its folder, and every item and its favourite slot travel
    /// with it (R-5). The items
    /// keep their contents; only their `NoteID`s change, which is what `renames` reports so an
    /// open item editor follows the note instead of concluding it is gone (ARCHITECTURE §4).
    private static func renameList(
        _ s: VaultSnapshot, from: String, to: String
    ) throws(GTDError) -> Reduction {
        guard let list = s.list(named: from) else { throw .invalid(Message.unknownList(from)) }
        let clean = try requireListName(to)
        guard clean != list.name else { return Reduction(snapshot: s) }
        // A case-only rename would ask a case-insensitive file system to move a folder onto
        // itself. Refused rather than attempted — see ARCHITECTURE §6.
        guard !GTDList.sameName(clean, list.name) else {
            throw .invalid(Message.listCaseOnlyRename)
        }
        if let existing = s.list(named: clean) { throw .titleCollision(existing.name) }

        let layout = s.config.layout
        let oldFolder = layout.listFolder(list.name)
        let newFolder = layout.listFolder(clean)

        var next = s
        var renames = RenameMap.empty
        for index in next.lists.indices where next.lists[index].name == list.name {
            next.lists[index] = GTDList(name: clean)
        }
        for index in next.listItems.indices where next.listItems[index].list == list.name {
            let item = next.listItems[index]
            let moved = NoteID(path: newFolder + item.id.path.dropFirst(oldFolder.count))
            next.listItems[index] = rekey(item, to: moved, list: clean)
            renames.record(item.id, as: moved)
        }
        // A favourite is a list name, so it follows the rename — otherwise it would name a
        // folder that is gone and drop out of the navbar.
        if let favourites = next.config.favouriteLists {
            next.config.favouriteLists = favourites.map {
                GTDList.sameName($0, list.name) ? clean : $0
            }
        }
        // So does its icon.
        if let icon = next.config.listIcon(for: list.name) {
            next.config.listIcons = next.config.listIcons.filter { !GTDList.sameName($0.key, list.name) }
            next.config.listIcons[clean] = icon
        }
        return Reduction(
            snapshot: next,
            extraOps: [.moveFolder(from: oldFolder, to: newFolder)],
            renames: renames)
    }

    /// L2/R-5 — removing a list moves its folder into `GTD/Trash/`, items and `Done/` log
    /// included. Nothing is deleted, the name is freed, and one undo brings the whole tree back.
    private static func removeList(_ s: VaultSnapshot, name: String) throws(GTDError) -> Reduction {
        guard let list = s.list(named: name) else { throw .invalid(Message.unknownList(name)) }
        let layout = s.config.layout
        var next = s
        next.lists.removeAll { $0.name == list.name }
        next.listItems.removeAll { $0.list == list.name }
        if var favourites = next.config.favouriteLists {
            favourites.removeAll { GTDList.sameName($0, list.name) }
            next.config.favouriteLists = favourites
        }
        next.config.listIcons = next.config.listIcons.filter { !GTDList.sameName($0.key, list.name) }
        return Reduction(
            snapshot: next,
            extraOps: [.moveFolder(
                from: layout.listFolder(list.name),
                to: "\(layout.trash)/\(list.name)")])
    }

    /// I4b/R-5 — which lists the inbox navbar shows, in the user's order. Writing it is what
    /// turns the derived default into a stored choice; until then `GTD/Config.md` has no
    /// `favouriteLists:` line at all.
    private static func setFavouriteLists(
        _ s: VaultSnapshot, names: [String]
    ) throws(GTDError) -> Reduction {
        var chosen: [String] = []
        for name in names {
            guard let list = s.list(named: name) else { throw .invalid(Message.unknownList(name)) }
            if !chosen.contains(list.name) { chosen.append(list.name) }
        }
        var next = s
        next.config.favouriteLists = chosen
        return Reduction(snapshot: next)
    }

    /// R-5 — the cleanup behind launch and the inbox's Knowledge / List card: a stored favourite
    /// whose folder is gone is dropped from `GTD/Config.md`. Kept as it is when nothing is stale,
    /// and when the vault shows no list at all — that is far likelier a `Lists/` folder not yet
    /// indexed or synced than every list gone, and pruning would throw the whole choice away.
    private static func pruneFavouriteLists(_ s: VaultSnapshot) -> Reduction {
        guard let stored = s.config.favouriteLists, !s.lists.isEmpty else {
            return Reduction(snapshot: s)
        }
        let kept = stored.filter { s.list(named: $0) != nil }
        guard kept.count < stored.count else { return Reduction(snapshot: s) }
        var next = s
        next.config.favouriteLists = kept
        return Reduction(snapshot: next)
    }

    /// L2 — the icon a list shows everywhere. Stored under the list's own spelling, so the
    /// config names the folder exactly; `nil` or an empty symbol removes the entry.
    private static func setListIcon(
        _ s: VaultSnapshot, list name: String, symbol: String?
    ) throws(GTDError) -> Reduction {
        guard let list = s.list(named: name) else { throw .invalid(Message.unknownList(name)) }
        let clean = symbol?.trimmingCharacters(in: .whitespaces) ?? ""
        var next = s
        next.config.listIcons = s.config.listIcons.filter { !GTDList.sameName($0.key, list.name) }
        if !clean.isEmpty { next.config.listIcons[list.name] = clean }
        return Reduction(snapshot: next)
    }

    /// A new item typed inside its list (L1). The title is the file name, so an empty one is
    /// refused (`titleRequired`) and a taken one is never overwritten (`titleCollision`) — the
    /// same two rules `updateListItem` applies. The note is brand new, so it is stamped with the
    /// env's `now`; the snapshot diff writes it because it appears in `listItems` at a path no
    /// entity had before. `Done/` is out of reach: a new item is always open.
    private static func addListItem(
        _ s: VaultSnapshot, list name: String, title: String, notes: String, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let list = s.list(named: name) else { throw .invalid(Message.unknownList(name)) }
        let clean = try requireTitle(title)
        let id = s.config.layout.listItemPath(list: list.name, title: clean)
        guard !pathExists(id, in: s) else { throw .titleCollision(clean) }
        var next = s
        next.listItems.append(ListItem(
            id: id,
            list: list.name,
            title: clean,
            isFinished: false,
            created: env.now,
            notes: notes))
        return Reduction(snapshot: next)
    }

    /// Editing one item (L1): the title is the file name, so changing it is a move — and, like
    /// every other rename in this app, it never overwrites (`titleCollision`).
    private static func updateListItem(
        _ s: VaultSnapshot, id: NoteID, title: String, notes: String
    ) throws(GTDError) -> Reduction {
        guard let index = s.listItems.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        let previous = s.listItems[index]
        let clean = try requireTitle(title)

        var updated = previous
        updated.title = clean
        updated.notes = notes

        var next = s
        var extraOps: [VaultFileOp] = []
        var renames = RenameMap.empty

        let wanted = s.config.layout.listItemPath(
            list: previous.list, title: clean, finished: previous.isFinished)
        if wanted != previous.id {
            guard !pathExists(wanted, in: s) else { throw .titleCollision(clean) }
            next.listItems[index] = rekey(updated, to: wanted, list: previous.list)
            extraOps.append(.move(from: previous.id.path, to: wanted.path))
            renames.record(previous.id, as: wanted)
        } else {
            next.listItems[index] = updated
        }
        return Reduction(snapshot: next, extraOps: extraOps, renames: renames)
    }

    /// L3 — checking an item off moves its note into `Lists/<name>/Done/`, where it stays as a
    /// log. Idempotent: an already-finished item is left exactly as it is.
    private static func completeListItem(_ s: VaultSnapshot, id: NoteID) throws(GTDError) -> Reduction {
        guard let index = s.listItems.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        let item = s.listItems[index]
        guard !item.isFinished else { return Reduction(snapshot: s) }

        let target = s.config.layout.listItemPath(list: item.list, title: item.title, finished: true)
        guard !pathExists(target, in: s) else { throw .titleCollision(item.title) }

        var moved = rekey(item, to: target, list: item.list)
        moved.isFinished = true
        var next = s
        next.listItems[index] = moved
        var renames = RenameMap.empty
        renames.record(item.id, as: target)
        return Reduction(
            snapshot: next,
            extraOps: [.move(from: item.id.path, to: target.path)],
            renames: renames)
    }

    /// I4c — the same rule as for an action: the entity leaves the snapshot naming no path, so
    /// the diff emits the `.delete` that `GTDVault` performs as a move into `GTD/Trash/`.
    private static func trashListItem(_ s: VaultSnapshot, id: NoteID) throws(GTDError) -> Reduction {
        guard s.listItem(id) != nil else { throw .notFound(id) }
        var next = s
        next.listItems.removeAll { $0.id == id }
        return Reduction(snapshot: next)
    }

    /// L4 "Make action" — the note **moves** to `Actions/` (nothing is re-created, so its
    /// `created` timestamp, its notes and any key the user added survive) and is then subject to
    /// exactly the rules of an inbox action filing: it goes through `makeAction` and the same
    /// `checkCap`, so the required-field validation of R-3 (T04) and the cap apply without this
    /// command knowing anything about either.
    private static func promoteListItem(
        _ s: VaultSnapshot, id: NoteID, draft: ActionDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let item = s.listItem(id) else { throw .notFound(id) }
        var next = s
        // L4 — the item's own notes are somebody else's content: they stay at the top of the
        // body and the action headings follow below them (R-4's shape), so nothing is lost.
        var filed = draft
        filed.preamble = CaptureText.filedBody(body: item.notes, notes: draft.preamble)
        let action = try makeAction(
            from: filed, in: &next, env: env, created: item.created, passthrough: item.passthrough)
        next.listItems.removeAll { $0.id == id }
        next.actions.append(action)
        try checkCap(old: s, new: next, today: env.today)
        var renames = RenameMap.empty
        renames.record(item.id, as: action.id)
        return Reduction(
            snapshot: next,
            extraOps: [.move(from: item.id.path, to: action.id.path)],
            renames: renames)
    }

    /// E3 — an action becomes a list item (the inverse of `promoteListItem`): the file moves
    /// into `Lists/<name>/`, keeps its `created` and its frontmatter passthrough, and its body
    /// (preamble, `Why?`, `What?`) becomes the item's notes so nothing the person wrote is
    /// lost. Undo moves it back. A list item is never an action, so the cap only ever drops.
    private static func moveActionToList(
        _ s: VaultSnapshot, id: NoteID, list name: String
    ) throws(GTDError) -> Reduction {
        guard let action = s.action(id) else { throw .notFound(id) }
        guard let list = s.list(named: name) else { throw .invalid(Message.unknownList(name)) }
        let target = s.config.layout.listItemPath(list: list.name, title: action.title)
        guard !pathExists(target, in: s) else { throw .titleCollision(action.title) }

        var next = s
        next.actions.removeAll { $0.id == id }
        retarget(from: id, to: nil, in: &next)
        next.listItems.append(ListItem(
            id: target,
            list: list.name,
            title: action.title,
            isFinished: false,
            created: action.created,
            notes: listNotes(of: action),
            passthrough: action.passthrough))
        var renames = RenameMap.empty
        renames.record(id, as: target)
        return Reduction(
            snapshot: next,
            extraOps: [.move(from: id.path, to: target.path)],
            renames: renames)
    }

    /// The item's notes: the action's preamble, then `Why?` / `What?` under their headings when
    /// they say anything — the same text, readable in Obsidian, nothing dropped.
    static func listNotes(of action: Action) -> String {
        var parts: [String] = []
        let preamble = action.preamble.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = action.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = action.what.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preamble.isEmpty { parts.append(preamble) }
        if !why.isEmpty { parts.append("# Why?\n" + why) }
        if !what.isEmpty { parts.append("# What?\n" + what) }
        return parts.joined(separator: "\n\n")
    }

    /// L2 — a list name is a folder name: non-empty after sanitising, and never the reserved
    /// `Done` (which is the finished-items log of *every* list, L3/D38).
    private static func requireListName(_ raw: String) throws(GTDError) -> String {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalid(Message.listNameRequired)
        }
        let name = VaultLayout.sanitize(raw)
        guard !VaultLayout.isReservedListName(name) else { throw .invalid(Message.listNameReserved) }
        return name
    }

    private static func rekey(_ item: ListItem, to id: NoteID, list: String) -> ListItem {
        ListItem(
            id: id,
            list: list,
            title: item.title,
            isFinished: item.isFinished,
            created: item.created,
            notes: item.notes,
            passthrough: item.passthrough)
    }

    // MARK: - Routines

    /// R5 — one entry per step per day per device. Re-logging a step replaces the earlier entry,
    /// so the day's file stays the single truth for this device (N3).
    private static func logRoutineStep(
        _ s: VaultSnapshot, routineID: NoteID, stepID: String, result: RoutineStepResult, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let routine = s.routine(routineID) else { throw .notFound(routineID) }
        guard routine.steps.contains(where: { $0.id == stepID }) else {
            throw .invalid(Message.unknownStep(stepID))
        }
        var next = s
        next.routineLog.removeAll {
            $0.day == env.today && $0.routine == routine.title
                && $0.step == stepID && $0.device == env.deviceID
        }
        next.routineLog.append(RoutineLogEntry(
            day: env.today,
            routine: routine.title,
            step: stepID,
            result: result,
            at: env.now,
            device: env.deviceID))
        return Reduction(snapshot: next)
    }

    // MARK: - Config and review

    /// A4/A3 — the settings that live in `GTD/Config.md`.
    private static func updateConfig(_ s: VaultSnapshot, config: GTDConfig) throws(GTDError) -> Reduction {
        guard config.nextCap > 0 else { throw .invalid(Message.capTooSmall) }
        var checked = config
        checked.contexts = dedupe(config.contexts.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        guard !checked.contexts.isEmpty else { throw .invalid(Message.contextsRequired) }
        checked.onTheGoContexts = dedupe(config.onTheGoContexts)
        let known = Set(checked.contexts)
        if let stray = checked.onTheGoContexts.first(where: { !known.contains($0) }) {
            throw .invalid(Message.unknownContext(stray))
        }
        var next = s
        next.config = checked
        return Reduction(snapshot: next)
    }

    /// §10.4 — the reducer only stores the review; `GTDServices` writes `KW <ww>.md` from the
    /// changed `lastReview` (`GTDModel` never produces markdown — ARCHITECTURE §4, T00-4).
    private static func saveWeeklyReview(
        _ s: VaultSnapshot, review: WeeklyReview, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard (1...53).contains(review.week) else { throw .invalid(Message.badWeek(review.week)) }
        guard review.year > 1970 else { throw .invalid(Message.badYear(review.year)) }
        var next = s
        var saved = review
        saved.savedAt = env.now
        next.lastReview = saved
        return Reduction(snapshot: next)
    }

    // MARK: - Archive

    /// A5 — done notes older than 30 days move to `Archive/YYYY/MM/` and leave the snapshot.
    /// Nothing is deleted, and nothing still open is ever touched.
    ///
    /// R-1 — a note still carrying the legacy `status: trash` is **not** archive material: it
    /// goes to `GTD/Trash/`, where the rework puts everything the user threw away (I4c).
    ///
    /// A promoted project step keeps pointing at the note it promoted, so the archive move
    /// **retargets** `ProjectStep.promotedTo` the same way a rename does (T41). Without that the
    /// `# Steps` line keeps a `→ [[Actions/…]]` wikilink to a file that is no longer there, which
    /// is a dead link in Obsidian and a `notFound` for anything in the app that follows it.
    private static func archiveCompleted(_ s: VaultSnapshot, env: ReducerEnv) -> Reduction {
        let candidates = Rules.archiveCandidates(s, today: env.today, calendar: env.calendar)
        guard !candidates.isEmpty else { return Reduction(snapshot: s) }
        var next = s
        var ops: [VaultFileOp] = []
        for action in candidates {
            let day = Rules.closedDay(action, calendar: env.calendar) ?? env.today
            let target = action.status == .legacyTrashed
                ? s.config.layout.trashPath(for: action.id)
                : s.config.layout.archivePath(for: action.id, completedOn: day)
            ops.append(.move(from: action.id.path, to: target.path))
            retarget(from: action.id, to: action.status == .legacyTrashed ? nil : target, in: &next)
        }
        let archived = Set(candidates.map(\.id))
        next.actions.removeAll { archived.contains($0.id) }
        return Reduction(snapshot: next, extraOps: ops)
    }

    // MARK: - Shared helpers

    /// Builds the action a draft describes, creating the project it names if that project is
    /// being created in the same step (I4a/R-8) — which is why the snapshot comes in `inout`.
    /// Does **not** check the cap: callers do that once on the finished snapshot, so one command
    /// never counts a slot twice.
    private static func makeAction(
        from draft: ActionDraft,
        in s: inout VaultSnapshot,
        env: ReducerEnv,
        created: Date? = nil,
        passthrough: NotePassthrough = .empty
    ) throws(GTDError) -> Action {
        var draft = draft
        draft.project = try resolveProject(for: draft, in: &s)
        let title = try requireTitle(draft.title)
        let id = s.config.layout.actionPath(title: title)
        guard !pathExists(id, in: s) else { throw .titleCollision(title) }

        var action = Action(
            id: id,
            title: title,
            status: draft.status,
            contexts: draft.contexts,
            timeEstimate: draft.timeEstimate,
            project: draft.project,
            deferDate: draft.deferDate,
            due: draft.due,
            created: created ?? env.now,
            preamble: draft.preamble,
            why: draft.why,
            what: draft.what,
            // Set when the note already exists and is only *moving* into `Actions/` (L4): the
            // codec then patches that file instead of rendering a new one, so its body and any
            // key the user added survive the promotion.
            passthrough: passthrough)
        try normalize(&action, previous: nil, waiting: draft.waiting, in: s, env: env)
        return action
    }

    /// Everything that must be true of an action after any command touched it.
    ///
    /// - W1/D39 `waiting` needs a **follow-up date**; who is optional. Leaving `waiting` clears both.
    /// - I4/D12/R-3 a *new* transition into a tier brings what that tier requires
    ///   (`RequiredField.missing`), and a note already in its tier is never judged again.
    /// - P3 only an active project may hold an action in Next.
    /// - A4 contexts come from the configured closed list (values already in the file survive).
    /// - A5 a closed action carries a closing date; re-opening one clears it.
    /// - R-1 nothing may move *into* the legacy `trash` state.
    /// - §1 `timeEstimate: 0` is never written.
    private static func normalize(
        _ action: inout Action,
        previous: Action?,
        waiting: WaitingInfo?,
        in s: VaultSnapshot,
        env: ReducerEnv
    ) throws(GTDError) {
        action.title = try requireTitle(action.title)
        action.contexts = try normalizeContexts(action.contexts, previous: previous?.contexts, in: s)

        // R-1/I4c — trash is not a status. A note that already carries the legacy `status: trash`
        // keeps it (the vault stays repairable); nothing may *move into* it.
        if !action.status.isUserSettable, previous?.status != action.status {
            throw .invalid(Message.trashIsNotAStatus)
        }

        if let estimate = action.timeEstimate, estimate <= 0 { action.timeEstimate = nil }

        if action.status == .waiting {
            // W1/D39 — the date is the commitment; who is optional, and an empty who writes no
            // `waitingFor:` line at all rather than an empty one.
            let info = waiting ?? action.waiting
            let who = (info?.who ?? "").trimmingCharacters(in: .whitespaces)
            action.waitingFor = who.isEmpty ? nil : who
            action.followUpDate = info?.followUp
        } else {
            action.waitingFor = nil
            action.followUpDate = nil
        }

        // A project this command sets has to exist. A link the note already carries is never
        // judged again: a project renamed or moved in Obsidian leaves it dangling (a vault issue),
        // and that must not stop the action from being ticked off or edited (#53).
        if let projectID = action.project {
            if let project = s.project(projectID) {
                if action.status.countsTowardCap, project.status != .active {
                    throw .invalid(Message.projectNotActive)
                }
            } else if projectID != previous?.project {
                throw .notFound(projectID)
            }
        }

        // R-3 — validation before leaving (STYLEGUIDE §3.6). It runs after the rules about the
        // *world* (a project must be active) and before the cap is counted, so a card that is
        // missing a field hears about the field rather than about the cap it never reached.
        let missing = RequiredField.missing(
            status: action.status,
            previous: previous?.status,
            why: action.why,
            what: action.what,
            contexts: action.contexts,
            timeEstimate: action.timeEstimate,
            followUpDate: action.followUpDate)
        guard missing.isEmpty else { throw .missingFields(missing) }

        // R-2 — a Next item may carry a future `defer`. It is hidden until its date and does not
        // occupy a slot while hidden (`Rules.countsTowardCap(_:today:)`); on its date it comes
        // back into Next with the `back` badge, and an over-cap Next is shown, never repaired
        // behind the user's back. The 2026-09-19 refusal is gone.

        if action.status.isClosed {
            if action.completedDate == nil { action.completedDate = env.now }
        } else {
            action.completedDate = nil
        }

        action.modified = env.now
    }

    /// A4 — contexts are a closed list. Values that are already in the note survive (a migrated
    /// vault is not the user's fault), but nothing unknown is ever added.
    private static func normalizeContexts(
        _ contexts: [String], previous: [String]?, in s: VaultSnapshot
    ) throws(GTDError) -> [String] {
        let cleaned = dedupe(contexts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let known = Set(s.config.contexts).union(previous ?? [])
        if let stray = cleaned.first(where: { !known.contains($0) }) {
            throw .invalid(Message.unknownContext(stray))
        }
        return cleaned
    }

    /// A1 — the title is the file name, so it must survive sanitising as something non-empty.
    private static func requireTitle(_ raw: String) throws(GTDError) -> String {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalid(Message.titleRequired)
        }
        return VaultLayout.sanitize(raw)
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// I4/A3 — the cap only blocks commands that *increase* Next occupancy, so a vault edited
    /// by hand into 17/15 can still be repaired from the app. Never automatic: the UI must
    /// offer "demote something" or cancel (D14).
    private static func checkCap(old: VaultSnapshot, new: VaultSnapshot, today: Day) throws(GTDError) {
        let cap = new.config.nextCap
        let after = Rules.countsTowardCap(new, today: today)
        guard after > cap, after > Rules.countsTowardCap(old, today: today) else { return }
        throw .nextCapReached(cap: cap)
    }

    private static func pathExists(_ id: NoteID, in s: VaultSnapshot) -> Bool {
        s.action(id) != nil || s.project(id) != nil || s.area(id) != nil
            || s.routine(id) != nil || s.inboxItem(id) != nil || s.listItem(id) != nil
    }

    private static func rekey(_ action: Action, to id: NoteID) -> Action {
        Action(
            id: id,
            title: action.title,
            status: action.status,
            contexts: action.contexts,
            timeEstimate: action.timeEstimate,
            project: action.project,
            deferDate: action.deferDate,
            due: action.due,
            waitingFor: action.waitingFor,
            followUpDate: action.followUpDate,
            created: action.created,
            completedDate: action.completedDate,
            reviewReason: action.reviewReason,
            modified: action.modified,
            body: action.body,
            passthrough: action.passthrough)
    }

    /// The wording of `GTDError.invalid`. `GTDError` is `Equatable`, so these strings are part
    /// of the contract tests compare against — they are not user-facing copy (that is
    /// `DesignSystem.Copy`).
    enum Message {
        static let titleRequired = "A title is required"
        static let reviewReasonRequired = "Defer to review needs a reason"
        static let projectNotActive = "Only active projects put actions into Next"
        static let trashIsNotAStatus = "Trash is not a status — trashing moves the note to GTD/Trash/"
        static let projectChoiceAmbiguous =
            "An action names either an existing project or a new one, not both"
        static let projectRenameUnsupported = "Renaming a project is not supported"
        static let areaNameReserved =
            "\"\(VaultLayout.noAreaFolderName)\" is the folder for projects without an area "
            + "and cannot be an area"
        static let stepAlreadyPromoted = "This step is already promoted"
        static let stepAlreadyDone = "This step is already done"
        static let linkClosedAction = "A finished action cannot become a step"
        static let actionInOtherProject = "This action belongs to another project"
        static let actionAlreadyAStep = "This action is already a step of the project"
        static let knowledgeTargetIsSource = "The knowledge note would overwrite the capture"
        static let listNameRequired = "A list name is required"
        static let listNameReserved =
            "\"\(VaultLayout.doneFolderName)\" is reserved for finished items and cannot be a list"
        static let listCaseOnlyRename = "Renaming a list only by capitalisation is not supported"
        static func unknownList(_ name: String) -> String { "Unknown list: \(name)" }
        static let capTooSmall = "Next cap must be at least 1"
        static let contextsRequired = "At least one context is required"
        static func unknownContext(_ value: String) -> String { "Unknown context: \(value)" }
        static func noCheckbox(_ index: Int) -> String { "No checkbox at index \(index)" }
        static func noStep(_ index: Int) -> String { "No step at index \(index)" }
        static func unknownStep(_ id: String) -> String { "Unknown routine step \(id)" }
        static func badWeek(_ week: Int) -> String { "Week \(week) is not a calendar week" }
        static func badYear(_ year: Int) -> String { "Year \(year) is not a plausible year" }
    }
}
