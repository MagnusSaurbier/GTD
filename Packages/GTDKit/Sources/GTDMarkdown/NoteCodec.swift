import Foundation
import GTDModel
import Yams

/// Markdown ⇄ model.
///
/// **Round-trip rule (N2).** `encode(decode(text)) == text`, byte for byte, for every note the
/// app can read — including unknown frontmatter keys, their order and formatting, unknown body
/// sections, CRLF, a missing final newline and a `---` inside the body.
///
/// The rule holds because encoding never re-serialises anything. `decode` stashes the original
/// file in `NotePassthrough`; `encode` re-reads that original, decodes it again into a
/// *reference* entity, and patches **only the lines whose value actually changed**. A field the
/// caller did not touch is not rewritten, so it cannot be reformatted.
///
/// Consequences worth knowing:
/// * Changing one field changes exactly one line (see `NoteCodecPatchTests`).
/// * A value the model cannot represent (`timeEstimate: 0`, an unknown key, a comment) survives
///   untouched; the codec never emits `timeEstimate: 0` itself (§1 "no lying defaults").
/// * An entity with an empty passthrough — one the app just created — is rendered from the
///   canonical template in `NoteTemplates`.
public enum NoteCodec {

    /// `NotePassthrough` slot holding the note's original text.
    static let sourceSlot = "source"

    /// The file text the entity was decoded from, byte for byte, or `nil` for an entity the app
    /// created. `GTDServices`' stale-write guard accepts it beside the entity's encoding, so a
    /// read-time normalisation — an inbox note without `created` takes the file's date, and
    /// encoding it would add the line — never counts as "changed elsewhere" (2026-09-25).
    public static func sourceText(of passthrough: NotePassthrough) -> String? {
        passthrough[sourceSlot]
    }

    // MARK: - Kind

    /// The `kind:` of a note (`project`, `area`, `review`, …), for callers that must dispatch
    /// to the right decoder. `nil` when the note has no frontmatter or no `kind`.
    public static func noteKind(text: String, path: String = "") -> String? {
        (try? FrontmatterDocument(text: text, path: path))?.scalar("kind")
    }

    // MARK: - Inbox

    /// The title is not read from the text: it is the file name (`InboxItem.title`, from `id`).
    ///
    /// `fileDate` is for a capture the app did not write — a note typed in Obsidian, a script's
    /// `echo > Inbox/x.md`: it has no `created`, and the honest answer to "when was this
    /// captured?" is then the file's own date — `GTDVault` passes its birth time (#89). A
    /// `created` that is present but unreadable is still an error; the fallback never papers over
    /// a broken value. The file is not touched: `created` is written the first time the app has a
    /// reason to write the note (`encode` stamps it, since the source text has none).
    public static func decodeInboxItem(
        id: NoteID, text: String, timeZone: TimeZone = .current, fileDate: Date? = nil
    ) throws -> InboxItem {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        let stated = doc.timestamp("created", defaultTimeZone: timeZone)
        guard let created = stated ?? (doc.hasKey("created") ? nil : fileDate) else {
            throw NoteCodecError.unreadable(
                path: id.path,
                reason: doc.hasKey("created")
                    ? "`created` is not a date: \(doc.scalar("created") ?? "")"
                    : "Missing `created`")
        }
        return InboxItem(
            id: id,
            body: RawText.text(doc.bodyLines),
            created: created,
            reviewReason: doc.scalar("reviewReason"),
            // #85 — a card closed half-way keeps its chips under the action keys.
            contexts: doc.list("contexts") ?? [],
            timeEstimate: doc.int("timeEstimate").flatMap { $0 > 0 ? $0 : nil },
            project: noteID(doc.scalar("project")),
            deferDate: doc.day("defer"),
            due: doc.day("due"),
            passthrough: passthrough(text))
    }

    public static func encode(_ item: InboxItem, timeZone: TimeZone = .current) -> String {
        let stored = item.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.inbox
        guard var doc = try? FrontmatterDocument(text: source, path: item.id.path) else { return source }
        let reference = stored.flatMap { try? decodeInboxItem(id: item.id, text: $0, timeZone: timeZone) }

        let order = Keys.inbox
        if reference?.created != item.created {
            doc.setValue("created", YAMLScalar.timestamp(item.created, timeZone: timeZone), canonicalOrder: order)
        }
        setOptionalText("reviewReason", item.reviewReason, reference?.reviewReason, &doc, order)
        setCardFields(
            contexts: item.contexts, timeEstimate: item.timeEstimate, project: item.project,
            deferDate: item.deferDate, due: item.due,
            reference: reference.map {
                ($0.contexts, $0.timeEstimate, $0.project, $0.deferDate, $0.due)
            },
            &doc, order)
        if reference?.body != item.body {
            doc.setBody(RawText.block(item.body, terminator: doc.terminator))
        }
        return doc.text
    }

    // MARK: - Action

    /// #86 — a legacy `defer:` line is read as what deferring means now: a who-less waiting
    /// item following up on that day (`Action.foldingDeferIntoWaiting`). Like R-1's status
    /// spellings, the file keeps its own lines until the user changes the note; `encode` then
    /// rewrites them as `status: waiting` + `followUpDate:` and drops `defer:`.
    public static func decodeAction(
        id: NoteID, text: String, timeZone: TimeZone = .current
    ) throws -> Action {
        try decodeStoredAction(id: id, text: text, timeZone: timeZone).foldingDeferIntoWaiting()
    }

    /// The frontmatter exactly as written, legacy `defer:` included — what `encode` patches.
    static func decodeStoredAction(
        id: NoteID, text: String, timeZone: TimeZone = .current
    ) throws -> Action {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        guard let statusRaw = doc.scalar("status") else {
            throw NoteCodecError.unreadable(path: id.path, reason: "Missing `status`")
        }
        // R-1 — tolerant read: `backlog` and `maybe` are the pre-2026-09-21 spellings of
        // `someday`, and `trash` is the legacy closed state. Because `encode` patches only the
        // lines whose *decoded* value changed, such a file keeps its own word on disk until the
        // status really changes: nothing is silently rewritten.
        guard let status = ActionStatus(tolerantRawValue: statusRaw) else {
            throw NoteCodecError.unreadable(
                path: id.path,
                reason: "Unknown `status` \"\(statusRaw)\" — expected one of "
                    + ActionStatus.acceptedRawValues.joined(separator: ", "))
        }
        return Action(
            id: id,
            title: id.title,
            status: status,
            contexts: doc.list("contexts") ?? [],
            // A legacy `timeEstimate: 0` means "undecided", never zero minutes (§1).
            timeEstimate: doc.int("timeEstimate").flatMap { $0 > 0 ? $0 : nil },
            project: noteID(doc.scalar("project")),
            deferDate: doc.day("defer"),
            due: doc.day("due"),
            waitingFor: doc.scalar("waitingFor"),
            followUpDate: doc.day("followUpDate"),
            created: doc.timestamp("created", defaultTimeZone: timeZone),
            completedDate: doc.timestamp("completedDate", defaultTimeZone: timeZone),
            reviewReason: doc.scalar("reviewReason"),
            modified: nil,
            // The whole body, as written. `Action.why`/`.what`/`.preamble` are views over it
            // (`GTDModel.NoteBody`): a note without either heading reads as one long `What?`.
            body: RawText.text(doc.bodyLines),
            passthrough: passthrough(text))
    }

    public static func encode(_ action: Action, timeZone: TimeZone = .current) -> String {
        let stored = action.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.action
        guard var doc = try? FrontmatterDocument(text: source, path: action.id.path) else { return source }
        let reference = stored.flatMap { try? decodeAction(id: action.id, text: $0, timeZone: timeZone) }
        let order = Keys.action

        if reference?.status != action.status {
            doc.setValue("status", action.status.rawValue, canonicalOrder: order)
        }
        setCardFields(
            contexts: action.contexts, timeEstimate: action.timeEstimate, project: action.project,
            deferDate: action.deferDate, due: action.due,
            reference: reference.map {
                ($0.contexts, $0.timeEstimate, $0.project, $0.deferDate, $0.due)
            },
            &doc, order)
        setOptionalText("waitingFor", action.waitingFor, reference?.waitingFor, &doc, order)
        setOptionalDay("followUpDate", action.followUpDate, reference?.followUpDate, &doc, order)
        setOptionalDate("created", action.created, reference?.created, &doc, order, timeZone)
        setOptionalDate("completedDate", action.completedDate, reference?.completedDate, &doc, order, timeZone)
        setOptionalText("reviewReason", action.reviewReason, reference?.reviewReason, &doc, order)

        // The body is one field (2026-09-24): the model holds it whole and the editor edits it
        // whole, so it is written whole — but only when its text changed, with the file's own
        // line terminator. A note nobody edited keeps every byte, blank lines included. For a
        // note that does not decode as an action (a list item being *moved* into `Actions/`,
        // L4) the reducer has already put the item's notes at the top of `action.body`.
        if RawText.text(doc.bodyLines) != action.body {
            doc.setBody(RawText.block(action.body, terminator: doc.terminator))
        }

        // #86 — the note still holds a legacy `defer:` that `decodeAction` folded into waiting.
        // Untouched, it keeps every byte; once anything changed — a line, or one of the folded
        // fields, whose patch above may have been a no-op against the folded reference — the
        // lines the fold stood in for are written out for real, against what the file says.
        let foldedFieldsChanged = reference.map {
            $0.status != action.status || $0.waitingFor != action.waitingFor
                || $0.followUpDate != action.followUpDate || $0.deferDate != action.deferDate
        } ?? false
        if let stored, doc.text != stored || foldedFieldsChanged,
           let written = try? decodeStoredAction(id: action.id, text: stored, timeZone: timeZone),
           written.deferDate != nil {
            if written.status != action.status {
                doc.setValue("status", action.status.rawValue, canonicalOrder: order)
            }
            setOptionalDay("defer", action.deferDate, written.deferDate, &doc, order)
            setOptionalText("waitingFor", action.waitingFor, written.waitingFor, &doc, order)
            setOptionalDay("followUpDate", action.followUpDate, written.followUpDate, &doc, order)
        }
        return doc.text
    }

    // MARK: - List item (§5a)

    /// One note in `Lists/<name>/` (L1). The **title is the file name**, the body is free notes,
    /// and the only key the app writes is the optional `created` timestamp — a list item carries
    /// no status, no context and no commitment (D17/D18).
    ///
    /// The list it belongs to and whether it is finished come from the path (L3): the folder is
    /// the only marker there is. `layout` is only needed to know where the lists root is.
    public static func decodeListItem(
        id: NoteID, text: String, layout: VaultLayout = .default, timeZone: TimeZone = .current
    ) throws -> ListItem {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        guard let list = layout.listName(of: id) else {
            throw NoteCodecError.unreadable(
                path: id.path, reason: "Not a list item: expected \(layout.lists)/<list>/<note>.md")
        }
        return ListItem(
            id: id,
            list: list,
            title: id.title,
            isFinished: layout.isFinishedListItem(id),
            created: doc.timestamp("created", defaultTimeZone: timeZone),
            notes: RawText.text(doc.bodyLines),
            passthrough: passthrough(text))
    }

    public static func encode(_ item: ListItem, timeZone: TimeZone = .current) -> String {
        let stored = item.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.listItem
        guard var doc = try? FrontmatterDocument(text: source, path: item.id.path) else { return source }
        // The stored text may be the note under its *previous* path — a capture being filed into
        // a list, or an item being renamed — so the reference is decoded against the item's own
        // list rather than the path the text came from. Only `created` and the body are patched;
        // neither depends on where the file sits.
        let reference = stored.flatMap {
            try? FrontmatterDocument(text: $0, path: item.id.path)
        }
        let referenceCreated = reference?.timestamp("created", defaultTimeZone: timeZone)
        let referenceNotes = reference.map { RawText.text($0.bodyLines) }

        setOptionalDate("created", item.created, referenceCreated, &doc, Keys.listItem, timeZone)
        if (referenceNotes ?? "") != item.notes {
            doc.setBody(RawText.block(item.notes, terminator: doc.terminator))
        }
        return doc.text
    }

    // MARK: - Area

    public static func decodeArea(id: NoteID, text: String) throws -> Area {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        let sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
        return Area(
            id: id,
            title: sections.sections.first?.title ?? id.title,
            passthrough: passthrough(text))
    }

    public static func encode(_ area: Area) -> String {
        let stored = area.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.area
        guard var doc = try? FrontmatterDocument(text: source, path: area.id.path) else { return source }
        let reference = stored.flatMap { try? decodeArea(id: area.id, text: $0) }

        if !doc.hasKey("kind") { doc.setValue("kind", "area", canonicalOrder: Keys.area) }
        if reference?.title != area.title {
            var sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
            if sections.sections.isEmpty {
                sections.prefix.insert(
                    RawLine(content: "# \(area.title)", terminator: doc.terminator), at: 0)
            } else {
                sections.sections[0].title = area.title
                sections.sections[0].headingLine.content = "# \(area.title)"
            }
            doc.setBody(sections.lines)
        }
        return doc.text
    }

    // MARK: - Project

    public static func decodeProject(id: NoteID, text: String) throws -> Project {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        guard let statusRaw = doc.scalar("status") else {
            throw NoteCodecError.unreadable(path: id.path, reason: "Missing `status`")
        }
        guard let status = ProjectStatus(rawValue: statusRaw) else {
            throw NoteCodecError.unreadable(
                path: id.path,
                reason: "Unknown project `status` \"\(statusRaw)\" — expected one of "
                    + ProjectStatus.allCases.map(\.rawValue).joined(separator: ", "))
        }
        let sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
        let stepLines = sections.index(of: "Steps").map { sections.sections[$0].contentLines } ?? []
        let logLines = sections.index(of: "Log").map { sections.sections[$0].contentLines } ?? []

        return Project(
            id: id,
            title: id.title,
            area: noteID(doc.scalar("area")),
            status: status,
            outcome: sections.text(of: "Outcome") ?? "",
            why: sections.text(of: "Why?") ?? "",
            steps: CheckboxList.parse(stepLines).map {
                ProjectStep(text: $0.text, done: $0.done, promotedTo: $0.promotedTo)
            },
            log: logLines.compactMap { logEntry($0.content) },
            referenceFiles: [],
            passthrough: passthrough(text))
    }

    public static func encode(_ project: Project) -> String {
        let stored = project.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.project
        guard var doc = try? FrontmatterDocument(text: source, path: project.id.path) else { return source }
        let reference = stored.flatMap { try? decodeProject(id: project.id, text: $0) }
        let order = Keys.project

        if !doc.hasKey("kind") { doc.setValue("kind", "project", canonicalOrder: order) }
        if reference?.status != project.status {
            doc.setValue("status", project.status.rawValue, canonicalOrder: order)
        }
        if reference?.area != project.area {
            if let area = project.area {
                doc.setValue("area", Wikilink.frontmatterValue(area), canonicalOrder: order)
            } else {
                doc.removeValue("area")
            }
        }

        var sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
        if (reference?.outcome ?? "") != project.outcome {
            sections.setText("Outcome", project.outcome, canonicalOrder: Headings.project)
        }
        if (reference?.why ?? "") != project.why {
            sections.setText("Why?", project.why, canonicalOrder: Headings.project)
        }
        if (reference?.steps ?? []) != project.steps {
            sections.setLines(
                "Steps",
                project.steps.map {
                    CheckboxList.render(text: $0.text, done: $0.done, promotedTo: $0.promotedTo)
                },
                canonicalOrder: Headings.project)
        }
        if (reference?.log ?? []) != project.log {
            sections.setLines(
                "Log",
                project.log.map { "- \($0.day.iso) \($0.text)" },
                canonicalOrder: Headings.project)
        }
        doc.setBody(sections.lines)
        return doc.text
    }

    // MARK: - Routine

    public static func decodeRoutine(id: NoteID, text: String) throws -> Routine {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        var time: DayTime?
        if let raw = doc.scalar("time") {
            guard let parsed = DayTime(hhmm: raw) else {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "`time` is not HH:mm: \(raw)")
            }
            time = parsed
        }
        var day: Weekday?
        if let raw = doc.scalar("day"), !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = Weekday(name: raw) else {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "`day` is not a weekday (e.g. Sunday): \(raw)")
            }
            day = parsed
        }
        var steps: [RoutineStep] = []
        for item in CheckboxList.parse(doc.bodyLines) {
            if item.depth == 0 {
                steps.append(RoutineStep(id: RoutineStep.slug(item.text), title: item.text))
            } else if !steps.isEmpty {
                steps[steps.count - 1].substeps.append(item.text)
            }
        }
        return Routine(
            id: id, title: id.title, time: time, day: day, steps: steps,
            passthrough: passthrough(text))
    }

    public static func encode(_ routine: Routine) -> String {
        let stored = routine.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.routine
        guard var doc = try? FrontmatterDocument(text: source, path: routine.id.path) else { return source }
        let reference = stored.flatMap { try? decodeRoutine(id: routine.id, text: $0) }

        if reference?.time != routine.time {
            if let time = routine.time {
                doc.setValue("time", YAMLScalar.quoted(time.hhmm), canonicalOrder: Keys.routine)
            } else {
                doc.removeValue("time")
            }
        }
        if reference?.day != routine.day {
            if let day = routine.day {
                doc.setValue("day", day.name, canonicalOrder: Keys.routine)
            } else {
                doc.removeValue("day")
            }
        }
        if (reference?.steps ?? []) != routine.steps {
            var rendered: [RawLine] = []
            for step in routine.steps {
                rendered.append(RawLine(
                    content: CheckboxList.render(text: step.title, done: false),
                    terminator: doc.terminator))
                for substep in step.substeps {
                    rendered.append(RawLine(
                        content: CheckboxList.render(text: substep, done: false, depth: 1),
                        terminator: doc.terminator))
                }
            }
            var body = doc.bodyLines
            if let range = CheckboxList.listRange(in: body) {
                body.replaceSubrange(range, with: rendered)
            } else {
                body.append(contentsOf: rendered)
            }
            doc.setBody(body)
        }
        return doc.text
    }

    // MARK: - Routine log

    /// One `GTD/RoutineLog/<yyyy-MM-dd>--<deviceID>.md` file. Day and device come from the
    /// file name, so the id has to be the real one.
    public static func decodeRoutineLog(
        id: NoteID, text: String, timeZone: TimeZone = .current
    ) throws -> [RoutineLogEntry] {
        guard let (day, device) = routineLogName(id) else {
            throw NoteCodecError.unreadable(
                path: id.path, reason: "File name is not `<yyyy-MM-dd>--<device>.md`")
        }
        let doc = try FrontmatterDocument(text: text, path: id.path)
        guard let rows = doc.mappings("entries") else {
            // `entries:` with nothing under it is a legitimately empty log (that is exactly what
            // `encodeRoutineLog([])` writes). `entries:` holding anything *else* is damage, and
            // returning [] for it would be dangerous: this is the one encoder that regenerates
            // the file, so the next logged step of the day would overwrite the user's history
            // with an empty log. Refuse instead — `GTDVault` turns it into a `VaultIssue` and
            // nothing is written over (T41).
            if doc.hasKey("entries"),
               doc.scalar("entries") != nil || doc.mappingNode("entries") != nil {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "`entries` is not a list of routine steps")
            }
            return []
        }

        return try rows.map { row in
            guard let routine = row["routine"]?.scalar?.string,
                  let step = row["step"]?.scalar?.string,
                  let resultRaw = row["result"]?.scalar?.string
            else {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "An `entries` row is missing routine/step/result")
            }
            guard let result = RoutineStepResult(rawValue: resultRaw) else {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "Unknown routine step result \"\(resultRaw)\"")
            }
            guard let atRaw = row["at"]?.scalar?.string,
                  let at = YAMLScalar.parseTimestamp(atRaw, defaultTimeZone: timeZone)
            else {
                throw NoteCodecError.unreadable(
                    path: id.path, reason: "An `entries` row has no readable `at` timestamp")
            }
            return RoutineLogEntry(
                day: day, routine: routine, step: step, result: result, at: at, device: device)
        }
    }

    /// All entries of one day/device log file.
    ///
    /// The only encoder that regenerates rather than patches: the log file is app-owned and
    /// append-only, and `[RoutineLogEntry]` carries no passthrough. Entries are ordered by `at`.
    public static func encodeRoutineLog(
        _ entries: [RoutineLogEntry], timeZone: TimeZone = .current
    ) -> String {
        var lines = ["---", "entries:"]
        for entry in entries.sorted(by: { $0.at < $1.at }) {
            lines.append("  - routine: \(YAMLScalar.quoted(entry.routine))")
            lines.append("    step: \(YAMLScalar.quoted(entry.step))")
            lines.append("    result: \(entry.result.rawValue)")
            lines.append("    at: \(YAMLScalar.timestamp(entry.at, timeZone: timeZone))")
        }
        lines.append("---")
        return lines.map { $0 + "\n" }.joined()
    }

    /// `2026-09-10--iPhone.md` → day + device.
    public static func routineLogName(_ id: NoteID) -> (day: Day, device: String)? {
        let stem = id.title
        guard let separator = stem.range(of: "--") else { return nil }
        guard let day = Day(iso: String(stem[..<separator.lowerBound])) else { return nil }
        let device = String(stem[separator.upperBound...])
        return device.isEmpty ? nil : (day, device)
    }

    // MARK: - Config

    public static func decodeConfig(id: NoteID, text: String) throws -> GTDConfig {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        var layout = VaultLayout.default
        if let node = doc.mappingNode("layout") {
            layout = VaultLayout(
                inbox: node["inbox"]?.scalar?.string ?? layout.inbox,
                actions: node["actions"]?.scalar?.string ?? layout.actions,
                archive: node["archive"]?.scalar?.string ?? layout.archive,
                projects: node["projects"]?.scalar?.string ?? layout.projects,
                knowledge: node["knowledge"]?.scalar?.string ?? layout.knowledge,
                lists: node["lists"]?.scalar?.string ?? layout.lists,
                routines: node["routines"]?.scalar?.string ?? layout.routines,
                routineLog: node["routineLog"]?.scalar?.string ?? layout.routineLog,
                reviews: node["reviews"]?.scalar?.string ?? layout.reviews,
                trash: node["trash"]?.scalar?.string ?? layout.trash,
                configFile: node["configFile"]?.scalar?.string ?? layout.configFile)
        }
        return GTDConfig(
            contexts: doc.list("contexts") ?? GTDConfig.default.contexts,
            onTheGoContexts: doc.list("onTheGoContexts") ?? GTDConfig.default.onTheGoContexts,
            nextCap: doc.int("nextCap") ?? GTDConfig.default.nextCap,
            // R-5 — absent means "the user has never chosen"; `Rules.favouriteLists` derives the
            // default. `nil` and `[]` are different answers and both survive a round trip.
            favouriteLists: doc.hasKey("favouriteLists") ? (doc.list("favouriteLists") ?? []) : nil,
            listIcons: listIcons(doc.mappingNode("listIcons")),
            layout: layout,
            passthrough: passthrough(text))
    }

    /// `listIcons:` is a plain `list name: symbol` mapping; an entry without a string on both
    /// sides is skipped rather than refused — a stray line costs one list its icon, nothing else.
    private static func listIcons(_ node: Node?) -> [String: String] {
        guard let mapping = node?.mapping else { return [:] }
        var icons: [String: String] = [:]
        for (key, value) in mapping {
            guard let name = key.scalar?.string, let symbol = value.scalar?.string,
                  !name.isEmpty, !symbol.isEmpty else { continue }
            icons[name] = symbol
        }
        return icons
    }

    public static func encode(_ config: GTDConfig) -> String {
        let stored = config.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.config
        guard var doc = try? FrontmatterDocument(text: source, path: config.layout.configFile)
        else { return source }
        let reference = stored.flatMap { try? decodeConfig(id: NoteID(path: config.layout.configFile), text: $0) }
        let order = Keys.config

        if reference?.contexts != config.contexts {
            doc.setValue("contexts", YAMLScalar.flowList(config.contexts), canonicalOrder: order)
        }
        if reference?.onTheGoContexts != config.onTheGoContexts {
            doc.setValue(
                "onTheGoContexts", YAMLScalar.flowList(config.onTheGoContexts), canonicalOrder: order)
        }
        if reference?.nextCap != config.nextCap {
            doc.setValue("nextCap", String(config.nextCap), canonicalOrder: order)
        }
        // R-5 — the derived default is never written: only a choice the user made puts the key
        // into the file, and clearing it back to `nil` takes the line out again.
        if reference?.favouriteLists != config.favouriteLists {
            if let favourites = config.favouriteLists {
                doc.setValue("favouriteLists", YAMLScalar.flowList(favourites), canonicalOrder: order)
            } else {
                doc.removeValue("favouriteLists")
            }
        }
        // Like favourites, only a picked icon puts `listIcons:` into the file.
        if reference?.listIcons ?? [:] != config.listIcons {
            if config.listIcons.isEmpty {
                doc.removeValue("listIcons")
            } else {
                let lines = ["listIcons:"] + config.listIcons.keys.sorted().map {
                    "  \(YAMLScalar.string($0)): \(YAMLScalar.string(config.listIcons[$0] ?? ""))"
                }
                doc.setLines("listIcons", lines, canonicalOrder: order)
            }
        }
        if reference?.layout != config.layout {
            let defaults = VaultLayout.default
            var lines = ["layout:"]
            func add(_ key: String, _ value: String, _ fallback: String) {
                guard value != fallback else { return }
                lines.append("  \(key): \(YAMLScalar.string(value))")
            }
            add("inbox", config.layout.inbox, defaults.inbox)
            add("actions", config.layout.actions, defaults.actions)
            add("archive", config.layout.archive, defaults.archive)
            add("projects", config.layout.projects, defaults.projects)
            add("knowledge", config.layout.knowledge, defaults.knowledge)
            add("lists", config.layout.lists, defaults.lists)
            add("routines", config.layout.routines, defaults.routines)
            add("routineLog", config.layout.routineLog, defaults.routineLog)
            add("reviews", config.layout.reviews, defaults.reviews)
            add("trash", config.layout.trash, defaults.trash)
            add("configFile", config.layout.configFile, defaults.configFile)
            if lines.count == 1 { doc.removeValue("layout") }
            else { doc.setLines("layout", lines, canonicalOrder: order) }
        }
        return doc.text
    }

    // MARK: - Weekly review

    public static func decodeWeeklyReview(
        id: NoteID, text: String, timeZone: TimeZone = .current
    ) throws -> WeeklyReview {
        let doc = try FrontmatterDocument(text: text, path: id.path)
        let fromPath = reviewPathNumbers(id)
        guard let year = doc.int("year") ?? fromPath?.year,
              let week = doc.int("week") ?? fromPath?.week
        else {
            throw NoteCodecError.unreadable(
                path: id.path, reason: "Neither frontmatter nor path give a year and week")
        }
        let sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
        let fixLines = sections.index(of: Headings.systemFixes)
            .map { sections.sections[$0].contentLines } ?? []

        return WeeklyReview(
            year: year,
            week: week,
            wantedToAchieve: sections.text(of: Headings.review[0]) ?? "",
            achieved: sections.text(of: Headings.review[1]) ?? "",
            behaviorToChange: sections.text(of: Headings.review[2]) ?? "",
            whatToStop: sections.text(of: Headings.review[3]) ?? "",
            howIGrew: sections.text(of: Headings.review[4]) ?? "",
            howToGrowFurther: sections.text(of: Headings.review[5]) ?? "",
            whatToTry: sections.text(of: Headings.review[6]) ?? "",
            goalForNextWeek: sections.text(of: Headings.review[7]) ?? "",
            systemFixNotes: fixLines.compactMap(bulletText),
            savedAt: doc.timestamp("savedAt", defaultTimeZone: timeZone),
            passthrough: passthrough(text))
    }

    public static func encode(_ review: WeeklyReview, timeZone: TimeZone = .current) -> String {
        let path = review.noteID().path
        let stored = review.passthrough[sourceSlot]
        let source = stored ?? NoteTemplates.review
        guard var doc = try? FrontmatterDocument(text: source, path: path) else { return source }
        let reference = stored.flatMap {
            try? decodeWeeklyReview(id: NoteID(path: path), text: $0, timeZone: timeZone)
        }
        let order = Keys.review

        if !doc.hasKey("kind") { doc.setValue("kind", "review", canonicalOrder: order) }
        if reference?.year != review.year { doc.setValue("year", String(review.year), canonicalOrder: order) }
        if reference?.week != review.week { doc.setValue("week", String(review.week), canonicalOrder: order) }
        setOptionalDate("savedAt", review.savedAt, reference?.savedAt, &doc, order, timeZone)

        var sections = BodySections(lines: doc.bodyLines, terminator: doc.terminator)
        let answers = [
            review.wantedToAchieve, review.achieved, review.behaviorToChange, review.whatToStop,
            review.howIGrew, review.howToGrowFurther, review.whatToTry, review.goalForNextWeek,
        ]
        let referenceAnswers = reference.map {
            [$0.wantedToAchieve, $0.achieved, $0.behaviorToChange, $0.whatToStop,
             $0.howIGrew, $0.howToGrowFurther, $0.whatToTry, $0.goalForNextWeek]
        } ?? Array(repeating: "", count: 8)
        for (index, heading) in Headings.review.enumerated() where answers[index] != referenceAnswers[index] {
            sections.setText(heading, answers[index], canonicalOrder: Headings.reviewAll)
        }
        if (reference?.systemFixNotes ?? []) != review.systemFixNotes {
            sections.setLines(
                Headings.systemFixes, review.systemFixNotes.map { "- \($0)" },
                canonicalOrder: Headings.reviewAll)
        }
        doc.setBody(sections.lines)
        return doc.text
    }

    // MARK: - Helpers

    static func passthrough(_ text: String) -> NotePassthrough {
        var carrier = NotePassthrough()
        carrier[sourceSlot] = text
        return carrier
    }

    /// A wikilink or bare path in frontmatter → `NoteID`.
    static func noteID(_ raw: String?) -> NoteID? {
        guard let raw, !raw.isEmpty else { return nil }
        if let link = Wikilink.parse(raw) { return link.noteID }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return NoteID(path: trimmed.hasSuffix(".md") ? trimmed : trimmed + ".md")
    }

    /// `- 2026-09-08 Collect DAAD transcripts` → a log entry. Anything else is ignored.
    static func logEntry(_ content: String) -> LogEntry? {
        guard let text = bulletText(RawLine(content: content, terminator: "")) else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let day = Day(iso: String(first)) else { return nil }
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return LogEntry(day: day, text: rest)
    }

    /// The text of a `- item` line, or `nil` when it is not a bullet.
    static func bulletText(_ line: RawLine) -> String? {
        let trimmed = line.content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// `GTD/Reviews/2026/KW 37.md` → (2026, 37).
    static func reviewPathNumbers(_ id: NoteID) -> (year: Int, week: Int)? {
        let parts = id.components
        guard parts.count >= 2, let year = Int(parts[parts.count - 2]) else { return nil }
        let stem = id.title
        let digits = stem.drop { !$0.isNumber }
        guard let week = Int(digits.prefix { $0.isNumber }) else { return nil }
        return (year, week)
    }

    // Free-text fields are always quoted: they routinely contain `:`, `#` and leading dashes.
    /// The five keys an action card decides, shared by actions and (#85) a half-processed
    /// inbox note. Each line is touched only when its value changed; an empty value removes the
    /// key, and `timeEstimate: 0` is never written (§1).
    private static func setCardFields(
        contexts: [String], timeEstimate: Int?, project: NoteID?, deferDate: Day?, due: Day?,
        reference: (contexts: [String], timeEstimate: Int?, project: NoteID?, deferDate: Day?, due: Day?)?,
        _ doc: inout FrontmatterDocument, _ order: [String]
    ) {
        if (reference?.contexts ?? []) != contexts {
            if contexts.isEmpty { doc.removeValue("contexts") }
            else { doc.setValue("contexts", YAMLScalar.flowList(contexts), canonicalOrder: order) }
        }
        if reference?.timeEstimate != timeEstimate {
            if let minutes = timeEstimate, minutes > 0 {
                doc.setValue("timeEstimate", String(minutes), canonicalOrder: order)
            } else {
                doc.removeValue("timeEstimate")
            }
        }
        if reference?.project != project {
            if let project {
                doc.setValue("project", Wikilink.frontmatterValue(project), canonicalOrder: order)
            } else {
                doc.removeValue("project")
            }
        }
        setOptionalDay("defer", deferDate, reference?.deferDate, &doc, order)
        setOptionalDay("due", due, reference?.due, &doc, order)
    }

    private static func setOptionalText(
        _ key: String, _ value: String?, _ reference: String?,
        _ doc: inout FrontmatterDocument, _ order: [String]
    ) {
        guard reference != value else { return }
        if let value, !value.isEmpty {
            doc.setValue(key, YAMLScalar.quoted(value), canonicalOrder: order)
        } else {
            doc.removeValue(key)
        }
    }

    private static func setOptionalDay(
        _ key: String, _ value: Day?, _ reference: Day?,
        _ doc: inout FrontmatterDocument, _ order: [String]
    ) {
        guard reference != value else { return }
        if let value { doc.setValue(key, YAMLScalar.day(value), canonicalOrder: order) }
        else { doc.removeValue(key) }
    }

    private static func setOptionalDate(
        _ key: String, _ value: Date?, _ reference: Date?,
        _ doc: inout FrontmatterDocument, _ order: [String], _ timeZone: TimeZone
    ) {
        guard reference != value else { return }
        if let value {
            doc.setValue(key, YAMLScalar.timestamp(value, timeZone: timeZone), canonicalOrder: order)
        } else {
            doc.removeValue(key)
        }
    }

    // MARK: - Canonical order

    /// Frontmatter key order used when the codec has to *insert* a key (REQUIREMENTS §5).
    /// Existing keys never move.
    public enum Keys {
        /// `created` first, as every capture has it; the card's keys (#85) after it.
        public static let inbox = [
            "created", "reviewReason", "contexts", "timeEstimate", "project", "defer", "due",
        ]
        public static let action = [
            "status", "contexts", "timeEstimate", "project", "defer", "due",
            "waitingFor", "followUpDate", "created", "completedDate", "reviewReason",
        ]
        /// A list item carries nothing else — that is the point of L1.
        public static let listItem = ["created"]
        public static let area = ["kind"]
        public static let project = ["kind", "status", "area"]
        public static let routine = ["time", "day"]
        public static let config = [
            "contexts", "onTheGoContexts", "nextCap", "favouriteLists", "listIcons", "layout",
        ]
        public static let review = ["kind", "year", "week", "savedAt"]
    }

    /// Body headings the codec understands. Matching is case- and punctuation-insensitive.
    public enum Headings {
        public static let action = ["Why?", "What?"]
        public static let project = ["Outcome", "Why?", "Steps", "Log"]
        public static let systemFixes = "System fixes"
        /// The eight questions of REQUIREMENTS §10.4, in order.
        public static let review = [
            "What did I want to achieve?",
            "What did I achieve?",
            "Which behavior do I want to change?",
            "What do I want to stop?",
            "How did I grow?",
            "How do I want to grow further?",
            "What do I want to try out?",
            "Goal for next week",
        ]
        public static let reviewAll = review + [systemFixes]
    }

    // MARK: - Validation helpers

    /// Contexts of `action` that are not in the configured closed list (A4).
    ///
    /// Unknown contexts are *not* a decode error: they are plain strings, so nothing is coerced
    /// or lost, and refusing the file would hide the action from the app entirely. `GTDVault`
    /// turns this into a `VaultIssue` instead.
    public static func unknownContexts(in action: Action, known: [String]) -> [String] {
        let set = Set(known.map { $0.lowercased() })
        return action.contexts.filter { !set.contains($0.lowercased()) }
    }
}

/// Canonical text for a note the app is creating from scratch (empty `NotePassthrough`).
/// Every encoder patches *into* these, so a new file has the same shape as an existing one.
enum NoteTemplates {
    static let inbox = "---\n---\n"
    static let action = "---\n---\n# Why?\n\n# What?\n"
    static let listItem = "---\n---\n"
    static let area = "---\nkind: area\n---\n"
    static let project = "---\n---\n# Outcome\n\n# Why?\n\n# Steps\n\n# Log\n"
    static let routine = "---\n---\n"
    static let config = "---\n---\n# Config\nSettings synced through the vault. Edited by the app.\n"
    static let review: String = {
        var body = ""
        for heading in NoteCodec.Headings.review { body += "# \(heading)\n\n" }
        body += "# \(NoteCodec.Headings.systemFixes)\n"
        return "---\n---\n" + body
    }()
}

public enum NoteCodecError: Error, Equatable {
    /// Placeholder kept from the T00 scaffold; nothing throws it any more.
    case notImplemented(String)
    /// A file the app will not guess about — surfaces as a `VaultIssue` (N3 §7.5).
    case unreadable(path: String, reason: String)

    /// The issue to show the user, so `GTDVault` never has to build the message itself.
    public var vaultIssue: VaultIssue {
        switch self {
        case let .notImplemented(what): VaultIssue(path: "", message: what)
        case let .unreadable(path, reason): VaultIssue(path: path, message: reason)
        }
    }
}
