import Foundation

/// The single place where GTD semantics live: cap enforcement, waiting validation, completion,
/// promotion, demotion, archive eligibility. UI and backends never re-implement any of it.
///
/// **Ownership:** T00 wrote this naïvely so that every `GTDCommand` already does something
/// sensible and the feature targets are usable against `InMemoryBackend`. **T11 hardens and fully
/// tests it.** Every knowingly-incomplete spot is marked `// T11:`.
///
/// ### How `extraOps` relates to the snapshot diff
/// `GTDServices` turns `Reduction` into file operations: it diffs old vs. new snapshot and
/// encodes changed entities. `extraOps` covers file effects the diff cannot express.
/// One rule makes the two agree: **a path mentioned in `extraOps` is owned by `extraOps`** — the
/// diff must not also emit an operation for it. That is why every command that makes a note
/// leave its collection (inbox filing, archiving, renaming, converting) emits the move itself.
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
            var next = s
            let action = try makeAction(from: draft, in: s, env: env)
            next.actions.append(action)
            try checkCap(old: s, new: next)
            return Reduction(snapshot: next)

        case let .updateAction(action):
            return try updateAction(s, action: action, env: env)

        case let .setStatus(id, status, waiting):
            return try setStatus(s, id: id, status: status, waiting: waiting, env: env)

        case let .complete(id):
            return try complete(s, id: id, env: env)

        case let .toggleCheckbox(id, index):
            return try toggleCheckbox(s, id: id, index: index)

        case let .convertActionToProject(id, draft):
            return try convertActionToProject(s, id: id, draft: draft, env: env)

        case let .createArea(title):
            var next = s
            _ = try addArea(title: title, to: &next)
            return Reduction(snapshot: next)

        case let .createProject(draft):
            var next = s
            _ = try addProject(draft, to: &next)
            return Reduction(snapshot: next)

        case let .updateProject(project):
            return try updateProject(s, project: project)

        case let .promoteStep(projectID, stepIndex, draft):
            return try promoteStep(s, projectID: projectID, stepIndex: stepIndex, draft: draft, env: env)

        case let .saveWeeklyReview(review):
            var next = s
            var saved = review
            saved.savedAt = env.now
            next.lastReview = saved
            // The note itself is written by GTDServices from the changed `lastReview`
            // (`NoteCodec.encode(_: WeeklyReview)`) — GTDModel never produces markdown.
            return Reduction(snapshot: next)

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
            guard config.nextCap > 0 else { throw .invalid("Next cap must be at least 1") }
            var next = s
            next.config = config
            return Reduction(snapshot: next)

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

    private static func deferInboxToReview(
        _ s: VaultSnapshot, id: NoteID, reason: String
    ) throws(GTDError) -> Reduction {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalid("Defer to review needs a reason") }
        guard let index = s.inbox.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var next = s
        next.inbox[index].reviewReason = trimmed
        return Reduction(snapshot: next)
    }

    private static func fileInbox(
        _ s: VaultSnapshot, id: NoteID, decision: InboxDecision, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let item = s.inboxItem(id) else { throw .notFound(id) }
        var next = s
        let layout = s.config.layout
        var extraOps: [VaultFileOp] = []

        switch decision {
        case let .action(draft):
            let action = try makeAction(from: draft, in: next, env: env, created: item.created)
            next.actions.append(action)
            extraOps.append(.delete(path: item.id.path))

        case let .knowledge(folder, title):
            let target = layout.knowledgePath(folder: folder, title: title)
            guard !pathExists(target, in: next) else { throw .titleCollision(title) }
            // The capture *becomes* the knowledge note: no content is rewritten, nothing is lost.
            extraOps.append(.move(from: item.id.path, to: target.path))

        case let .newProject(draft, firstActions):
            let project = try addProject(draft, to: &next)
            for actionDraft in firstActions {
                var linked = actionDraft
                linked.project = project.id
                let action = try makeAction(from: linked, in: next, env: env, created: item.created)
                next.actions.append(action)
            }
            extraOps.append(.delete(path: item.id.path))

        case let .existingProject(projectID, actions):
            guard next.project(projectID) != nil else { throw .notFound(projectID) }
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
        try checkCap(old: s, new: next)
        return Reduction(snapshot: next, extraOps: extraOps)
    }

    // MARK: - Actions

    private static func updateAction(
        _ s: VaultSnapshot, action: Action, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == action.id }) else {
            throw .notFound(action.id)
        }
        var updated = action
        try validate(&updated, waiting: action.waiting, in: s, env: env)

        var next = s
        var extraOps: [VaultFileOp] = []

        // A title change is a file move: the filename is the title (A1).
        let wantedID = s.config.layout.actionPath(title: updated.title)
        if wantedID != updated.id {
            guard !pathExists(wantedID, in: s) else { throw .titleCollision(updated.title) }
            let moved = rekey(updated, to: wantedID)
            next.actions[index] = moved
            extraOps.append(.move(from: updated.id.path, to: wantedID.path))
            // T11/T16: wikilinks pointing at the old path are rewritten by GTDServices.
        } else {
            next.actions[index] = updated
        }

        try checkCap(old: s, new: next)
        return Reduction(snapshot: next, extraOps: extraOps)
    }

    private static func setStatus(
        _ s: VaultSnapshot, id: NoteID, status: ActionStatus, waiting: WaitingInfo?, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var updated = s.actions[index]
        updated.status = status
        try validate(&updated, waiting: waiting, in: s, env: env)

        var next = s
        next.actions[index] = updated
        try checkCap(old: s, new: next)

        if status == .done {
            return try complete(next, id: id, env: env)
        }
        return Reduction(snapshot: next)
    }

    private static func complete(
        _ s: VaultSnapshot, id: NoteID, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let index = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        var next = s
        next.actions[index].status = .done
        next.actions[index].completedDate = env.now
        next.actions[index].waitingFor = nil
        next.actions[index].followUpDate = nil

        var prompts: [AppPrompt] = []
        if let projectID = next.actions[index].project,
           let projectIndex = next.projects.firstIndex(where: { $0.id == projectID }) {
            let title = next.actions[index].title
            next.projects[projectIndex].log.append(LogEntry(day: env.today, text: title))
            if let stepIndex = next.projects[projectIndex].steps.firstIndex(where: { $0.promotedTo == id }) {
                next.projects[projectIndex].steps[stepIndex].done = true
            }
            prompts.append(.whatsNext(project: projectID))   // P5
        }
        return Reduction(snapshot: next, prompts: prompts)
    }

    private static func toggleCheckbox(
        _ s: VaultSnapshot, id: NoteID, index: Int
    ) throws(GTDError) -> Reduction {
        guard let actionIndex = s.actions.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        let what = s.actions[actionIndex].what
        var lines = what.components(separatedBy: "\n")
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
        guard toggled else { throw .invalid("No checkbox at index \(index)") }
        var next = s
        next.actions[actionIndex].what = lines.joined(separator: "\n")
        return Reduction(snapshot: next)
    }

    private static func flipMark(_ line: String) -> String {
        if let range = line.range(of: "[ ]") { return line.replacingCharacters(in: range, with: "[x]") }
        if let range = line.range(of: "[x]") { return line.replacingCharacters(in: range, with: "[ ]") }
        if let range = line.range(of: "[X]") { return line.replacingCharacters(in: range, with: "[ ]") }
        return line
    }

    // MARK: - Projects

    private static func convertActionToProject(
        _ s: VaultSnapshot, id: NoteID, draft: ProjectDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let action = s.action(id) else { throw .notFound(id) }
        var next = s
        var effective = draft
        if effective.steps.isEmpty {
            effective.steps = action.checkboxes.map(\.text)
        }
        if effective.why.isEmpty { effective.why = action.why }
        _ = try addProject(effective, to: &next)
        // The action is superseded by the project note; its file moves to the trash folder
        // (the app never hard-deletes — ARCHITECTURE §3).
        // T11: decide whether the first step should be auto-promoted back into this action instead.
        next.actions.removeAll { $0.id == id }
        return Reduction(
            snapshot: next,
            extraOps: [.move(from: id.path, to: s.config.layout.trashPath(for: id).path)])
    }

    private static func updateProject(
        _ s: VaultSnapshot, project: Project
    ) throws(GTDError) -> Reduction {
        guard let index = s.projects.firstIndex(where: { $0.id == project.id }) else {
            throw .notFound(project.id)
        }
        let wasActive = s.projects[index].status == .active
        var next = s
        next.projects[index] = project

        // P3: only active projects put actions into Next.
        if wasActive, project.status != .active {
            for actionIndex in next.actions.indices
            where next.actions[actionIndex].project == project.id
                && next.actions[actionIndex].status.countsTowardCap {
                next.actions[actionIndex].status = .backlog
            }
        }
        return Reduction(snapshot: next)
    }

    private static func promoteStep(
        _ s: VaultSnapshot, projectID: NoteID, stepIndex: Int, draft: ActionDraft, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let projectIndex = s.projects.firstIndex(where: { $0.id == projectID }) else {
            throw .notFound(projectID)
        }
        guard s.projects[projectIndex].steps.indices.contains(stepIndex) else {
            throw .invalid("No step at index \(stepIndex)")
        }
        var next = s
        var linked = draft
        linked.project = projectID
        let action = try makeAction(from: linked, in: next, env: env)
        next.actions.append(action)
        next.projects[projectIndex].steps[stepIndex].promotedTo = action.id
        try checkCap(old: s, new: next)
        return Reduction(snapshot: next)
    }

    @discardableResult
    private static func addArea(title: String, to s: inout VaultSnapshot) throws(GTDError) -> Area {
        let id = s.config.layout.areaPath(title: title)
        guard !pathExists(id, in: s) else { throw .titleCollision(title) }
        let area = Area(id: id, title: VaultLayout.sanitize(title))
        s.areas.append(area)
        return area
    }

    @discardableResult
    private static func addProject(_ draft: ProjectDraft, to s: inout VaultSnapshot) throws(GTDError) -> Project {
        var areaID = draft.area
        if let newAreaTitle = draft.newAreaTitle,
           !newAreaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            areaID = try addArea(title: newAreaTitle, to: &s).id
        }
        if let areaID, s.area(areaID) == nil { throw .notFound(areaID) }

        let id = s.config.layout.projectPath(title: draft.title, inArea: areaID)
        guard !pathExists(id, in: s) else { throw .titleCollision(draft.title) }
        let project = Project(
            id: id,
            title: VaultLayout.sanitize(draft.title),
            area: areaID,
            status: .active,
            outcome: draft.outcome,
            why: draft.why,
            steps: draft.steps.map { ProjectStep(text: $0) })
        s.projects.append(project)
        return project
    }

    // MARK: - Routines

    private static func logRoutineStep(
        _ s: VaultSnapshot, routineID: NoteID, stepID: String, result: RoutineStepResult, env: ReducerEnv
    ) throws(GTDError) -> Reduction {
        guard let routine = s.routine(routineID) else { throw .notFound(routineID) }
        guard routine.steps.contains(where: { $0.id == stepID }) else {
            throw .invalid("Unknown routine step \(stepID)")
        }
        var next = s
        // Re-logging a step replaces the earlier entry for the same day, routine and device (R5).
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

    // MARK: - Archive

    private static func archiveCompleted(_ s: VaultSnapshot, env: ReducerEnv) -> Reduction {
        let candidates = Rules.archiveCandidates(s, today: env.today)
        guard !candidates.isEmpty else { return Reduction(snapshot: s) }
        var next = s
        var ops: [VaultFileOp] = []
        for action in candidates {
            let day = action.completedDate.map { Day($0, calendar: env.calendar) } ?? env.today
            let target = s.config.layout.archivePath(for: action.id, completedOn: day)
            ops.append(.move(from: action.id.path, to: target.path))
        }
        let archived = Set(candidates.map(\.id))
        next.actions.removeAll { archived.contains($0.id) }
        return Reduction(snapshot: next, extraOps: ops)
    }

    // MARK: - Shared helpers

    /// Builds the action a draft describes, validating waiting info and the project rule.
    /// Does **not** check the cap — callers do that once on the finished snapshot.
    private static func makeAction(
        from draft: ActionDraft,
        in s: VaultSnapshot,
        env: ReducerEnv,
        created: Date? = nil
    ) throws(GTDError) -> Action {
        let id = s.config.layout.actionPath(title: draft.title)
        guard !pathExists(id, in: s) else { throw .titleCollision(draft.title) }

        var action = Action(
            id: id,
            title: VaultLayout.sanitize(draft.title),
            status: draft.status,
            contexts: draft.contexts,
            timeEstimate: draft.timeEstimate.flatMap { $0 > 0 ? $0 : nil },
            project: draft.project,
            deferDate: draft.deferDate,
            due: draft.due,
            created: created ?? env.now,
            modified: env.now,
            why: draft.why,
            what: draft.what)
        try validate(&action, waiting: draft.waiting, in: s, env: env)
        return action
    }

    /// W1 (waiting needs who + follow-up) and P3 (only active projects reach Next).
    private static func validate(
        _ action: inout Action, waiting: WaitingInfo?, in s: VaultSnapshot, env: ReducerEnv
    ) throws(GTDError) {
        if action.status == .waiting {
            let info = waiting ?? action.waiting
            guard let info, !info.who.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw .waitingInfoRequired
            }
            action.waitingFor = info.who
            action.followUpDate = info.followUp
        } else {
            // Leaving `waiting` clears both halves — an empty field must not lie.
            action.waitingFor = nil
            action.followUpDate = nil
        }

        if action.status.countsTowardCap, let projectID = action.project {
            guard let project = s.project(projectID) else { throw .notFound(projectID) }
            guard project.status == .active else {
                throw .invalid("Only active projects put actions into Next")
            }
        }

        if let estimate = action.timeEstimate, estimate <= 0 {
            action.timeEstimate = nil   // `timeEstimate: 0` is forbidden (§1)
        }
        action.modified = env.now
    }

    /// I4/A3 — the cap only blocks commands that *increase* Next occupancy, so a vault edited
    /// by hand into 17/15 can still be repaired by the app.
    private static func checkCap(old: VaultSnapshot, new: VaultSnapshot) throws(GTDError) {
        let cap = new.config.nextCap
        let after = Rules.countsTowardCap(new)
        guard after > cap, after > Rules.countsTowardCap(old) else { return }
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
}
