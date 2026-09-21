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
/// | W1 waiting needs who + follow-up, leaving clears both | `normalize` |
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
        switch c {
        case let .editInboxText(id, text):
            return try editInboxText(s, id: id, text: text)

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

    private static func editInboxText(
        _ s: VaultSnapshot, id: NoteID, text: String
    ) throws(GTDError) -> Reduction {
        guard let index = s.inbox.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var next = s
        next.inbox[index].text = text
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

    /// I4 — the five destinations of a card. The capture file always leaves `Inbox/`:
    /// the knowledge decision **moves** it (keeping its `created` frontmatter and its text),
    /// every other decision trashes it after its content has become one or more new notes.
    private static func fileInbox(
        _ s: VaultSnapshot, id: NoteID, decision: InboxDecision, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let item = s.inboxItem(id) else { throw .notFound(id) }
        var next = s
        let layout = s.config.layout
        var extraOps: [VaultFileOp] = []
        var prompts: [AppPrompt] = []

        switch decision {
        case let .action(draft):
            let action = try makeAction(from: draft, in: next, env: env, created: item.created)
            next.actions.append(action)
            extraOps.append(.delete(path: item.id.path))

        case let .knowledge(folder, title):
            let noteTitle = try requireTitle(title)
            let target = layout.knowledgePath(folder: folder, title: noteTitle)
            guard !pathExists(target, in: next) else { throw .titleCollision(title) }
            guard target != item.id else { throw .invalid(Message.knowledgeTargetIsSource) }
            // The capture *becomes* the knowledge note: nothing is rewritten, nothing is lost (I4).
            extraOps.append(.move(from: item.id.path, to: target.path))

        case let .newProject(draft, firstActions):
            let project = try addProject(draft, to: &next)
            for actionDraft in firstActions {
                var linked = actionDraft
                linked.project = project.id
                let action = try makeAction(from: linked, in: next, env: env, created: item.created)
                next.actions.append(action)
            }
            if firstActions.isEmpty { prompts.append(.whatsNext(project: project.id)) }  // P4/P5
            extraOps.append(.delete(path: item.id.path))

        case let .existingProject(projectID, actions):
            guard next.project(projectID) != nil else { throw .notFound(projectID) }
            guard !actions.isEmpty else { throw .invalid(Message.projectNeedsAction) }
            for actionDraft in actions {
                var linked = actionDraft
                linked.project = projectID
                let action = try makeAction(from: linked, in: next, env: env, created: item.created)
                next.actions.append(action)
            }
            extraOps.append(.delete(path: item.id.path))

        case .trash:
            extraOps.append(.delete(path: item.id.path))
        }

        next.inbox.removeAll { $0.id == id }
        try checkCap(old: s, new: next, today: env.today)
        return Reduction(snapshot: next, prompts: prompts, extraOps: extraOps)
    }

    // MARK: - Actions

    private static func createAction(
        _ s: VaultSnapshot, draft: ActionDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        var next = s
        let action = try makeAction(from: draft, in: s, env: env)
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
    /// demotes them to Someday. Renaming or re-filing a project is not supported in v1: the
    /// folder name is the identity, so the title must keep matching the note's path.
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
        guard project.area == previous.area else { throw .invalid(Message.projectMoveUnsupported) }
        if let areaID = project.area, s.area(areaID) == nil { throw .notFound(areaID) }

        var next = s
        next.projects[index] = project

        if project.status != .active {
            for actionIndex in next.actions.indices
            where next.actions[actionIndex].project == project.id
                && next.actions[actionIndex].status.countsTowardCap {
                next.actions[actionIndex].status = .someday
                next.actions[actionIndex].modified = env.now
            }
        }
        return Reduction(snapshot: next)
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
        let action = try makeAction(from: linked, in: next, env: env)
        next.actions.append(action)
        next.projects[projectIndex].steps[stepIndex].promotedTo = action.id
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

    /// Builds the action a draft describes. Does **not** check the cap — callers do that once
    /// on the finished snapshot, so one command never counts a slot twice.
    private static func makeAction(
        from draft: ActionDraft,
        in s: VaultSnapshot,
        env: ReducerEnv,
        created: Date? = nil
    ) throws(GTDError) -> Action {
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
            why: draft.why,
            what: draft.what)
        try normalize(&action, previous: nil, waiting: draft.waiting, in: s, env: env)
        return action
    }

    /// Everything that must be true of an action after any command touched it.
    ///
    /// - W1 `waiting` needs who **and** follow-up; leaving `waiting` clears both.
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
            let info = waiting ?? action.waiting
            guard let info, !info.who.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw .waitingInfoRequired
            }
            action.waitingFor = info.who.trimmingCharacters(in: .whitespaces)
            action.followUpDate = info.followUp
        } else {
            action.waitingFor = nil
            action.followUpDate = nil
        }

        if let projectID = action.project {
            guard let project = s.project(projectID) else { throw .notFound(projectID) }
            if action.status.countsTowardCap, project.status != .active {
                throw .invalid(Message.projectNotActive)
            }
        }

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
            || s.routine(id) != nil || s.inboxItem(id) != nil
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
            why: action.why,
            what: action.what,
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
        static let projectNeedsAction = "Filing to a project needs at least one action"
        static let projectRenameUnsupported = "Renaming a project is not supported"
        static let projectMoveUnsupported = "Moving a project to another area is not supported"
        static let stepAlreadyPromoted = "This step is already promoted"
        static let stepAlreadyDone = "This step is already done"
        static let knowledgeTargetIsSource = "The knowledge note would overwrite the capture"
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
