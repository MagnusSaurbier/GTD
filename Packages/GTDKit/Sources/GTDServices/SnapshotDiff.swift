import Foundation
import GTDMarkdown
import GTDModel

/// Turns "the snapshot used to look like this, now it looks like that" into file operations.
///
/// ### The one rule that keeps this honest
/// A path already named in `Reduction.extraOps` is **owned by `extraOps`** (ARCHITECTURE §4,
/// T00-1): the diff emits no operation of its own for it. That is what lets the reducer decide
/// *where* a note goes when it leaves its collection (trash, archive, `Knowledge/`, a new name)
/// while the diff only ever answers *what is in the file*.
///
/// Three cases follow from it:
/// * **Removed and named in `extraOps`** — nothing. The move/delete is already there.
/// * **Removed and not named** — `.delete`, which `GTDVault` performs as a move into
///   `GTD/Trash/` (nothing is ever hard-deleted).
/// * **Renamed** (an `extraOps` move from an old entity path to a new one) — the move stays, and
///   a `.put` at the *new* path follows it only if the note's content also changed. The put comes
///   after the move, so one command that renames a note and edits it stays a single transaction.
///
/// ### Writing as little as possible
/// A `.put` is emitted only when `NoteCodec.encode(new) != NoteCodec.encode(old)`. Because the
/// codec patches the original file text it kept in `NotePassthrough`, encoding an untouched
/// entity reproduces its file byte for byte — so "the encoding changed" means exactly "the file
/// would change". Untouched notes keep their modification date (the staleness signals depend on
/// it) and no undo entry ever hashes a file nobody wrote.
public enum SnapshotDiff {

    /// Every operation the command needs, in application order: `extraOps` first (moves and
    /// trash), then the content writes.
    ///
    /// - Parameter timeZone: time zone new timestamps are written in (T10-1). `VaultBackend`
    ///   passes the reducer's, so a command and the file it writes agree.
    public static func ops(
        from old: VaultSnapshot,
        to new: VaultSnapshot,
        extraOps: [VaultFileOp],
        filedNotes: [FiledNote] = [],
        timeZone: TimeZone = .current
    ) throws -> [VaultFileOp] {
        let owned = Ownership(extraOps)
        var puts: [VaultFileOp] = []

        func diff<T: Equatable>(
            _ oldItems: [T],
            _ newItems: [T],
            id: (T) -> NoteID,
            encode: (T) -> String
        ) {
            var oldByPath: [String: T] = [:]
            for item in oldItems { oldByPath[id(item).path] = item }
            var newPaths = Set<String>()

            for item in newItems {
                let path = id(item).path
                newPaths.insert(path)
                // Unchanged, renamed, or brand new — in all three cases the question is the same:
                // does the file that will carry this entity differ from what it says now?
                let previous = oldByPath[path] ?? owned.source(of: path).flatMap { oldByPath[$0] }
                if let previous {
                    // `encode` is a pure function of the entity, so equal entities encode
                    // identically — and one command changes one of them. Without this line the
                    // diff encodes **every** note in the vault twice per command (T41: 4.4 s for
                    // one `setStatus` on a 1 000-note vault). A rename never takes this path:
                    // `previous` then carries the old `NoteID`, so it is never equal to `item`.
                    if previous == item { continue }
                    let text = encode(item)
                    if encode(previous) != text { puts.append(.put(path: path, text: text)) }
                } else {
                    puts.append(.put(path: path, text: encode(item)))
                }
            }

            for item in oldItems {
                let path = id(item).path
                guard !newPaths.contains(path), !owned.owns(path) else { continue }
                // Left the snapshot and nobody said where it went: the trash (T00-1).
                puts.append(.delete(path: path))
            }
        }

        diff(old.inbox, new.inbox, id: \.id) { NoteCodec.encode($0, timeZone: timeZone) }
        diff(old.actions, new.actions, id: \.id) { NoteCodec.encode($0, timeZone: timeZone) }
        diff(old.listItems, new.listItems, id: \.id) { NoteCodec.encode($0, timeZone: timeZone) }
        diff(old.areas, new.areas, id: \.id) { NoteCodec.encode($0) }
        diff(old.projects, new.projects, id: \.id) { NoteCodec.encode($0) }
        diff(old.routines, new.routines, id: \.id) { NoteCodec.encode($0) }

        appendFiledNotes(filedNotes, timeZone: timeZone, into: &puts)
        appendConfig(from: old, to: new, owned: owned, into: &puts)
        appendReview(from: old, to: new, owned: owned, timeZone: timeZone, into: &puts)
        appendRoutineLog(from: old, to: new, owned: owned, timeZone: timeZone, into: &puts)

        return extraOps + puts
    }

    /// The notes that live in no collection: the Knowledge note a capture becomes (I4b). The
    /// reducer said what the note says, this is where it becomes markdown — the same division of
    /// labour as the weekly review note (`GTDModel` never produces markdown, ARCHITECTURE §6).
    ///
    /// A filed note has the shape of a capture — an optional `created` and a free body — which
    /// is exactly what it was a moment ago, so it is encoded as one. Its own text comes along as
    /// the source, so unknown frontmatter keys survive; the **body is replaced outright**, so
    /// what lands on disk is what the reducer decided and never a stale copy of the capture.
    /// The put follows the `extraOps` move, so it patches the note where it now lives.
    private static func appendFiledNotes(
        _ notes: [FiledNote], timeZone: TimeZone, into puts: inout [VaultFileOp]
    ) {
        for note in notes {
            let item = InboxItem(
                id: note.id,
                body: note.body,
                created: note.created,
                passthrough: note.source)
            puts.append(.put(path: note.id.path, text: NoteCodec.encode(item, timeZone: timeZone)))
        }
    }

    // MARK: - The three collections that are not `[Entity]`

    /// `GTD/Config.md`. Written only by `updateConfig` — the reducer copies the config forward
    /// untouched otherwise, so the encoding is identical and nothing is written.
    private static func appendConfig(
        from old: VaultSnapshot, to new: VaultSnapshot, owned: Ownership,
        into puts: inout [VaultFileOp]
    ) {
        let path = new.config.layout.configFile
        guard !owned.owns(path) else { return }
        let text = NoteCodec.encode(new.config)
        guard text != NoteCodec.encode(old.config) else { return }
        puts.append(.put(path: path, text: text))
    }

    /// `GTD/Reviews/<yyyy>/KW <ww>.md` — T00-4: the reducer stores `lastReview`, `GTDServices`
    /// writes the note. An older review arriving through a sync never rewrites anything: only a
    /// *changed* `lastReview` is encoded.
    private static func appendReview(
        from old: VaultSnapshot, to new: VaultSnapshot, owned: Ownership, timeZone: TimeZone,
        into puts: inout [VaultFileOp]
    ) {
        guard let review = new.lastReview, review != old.lastReview else { return }
        let path = review.noteID(layout: new.config.layout).path
        guard !owned.owns(path) else { return }
        puts.append(.put(path: path, text: NoteCodec.encode(review, timeZone: timeZone)))
    }

    /// `GTD/RoutineLog/<yyyy-MM-dd>--<device>.md` — one file per day **per device** (R5, N3).
    /// The snapshot holds the last 14 days of every device's log; a file is rewritten only when
    /// its own day/device group changed, so this device never rewrites another device's file.
    /// Log files are never deleted, whatever leaves the 14-day window.
    private static func appendRoutineLog(
        from old: VaultSnapshot, to new: VaultSnapshot, owned: Ownership, timeZone: TimeZone,
        into puts: inout [VaultFileOp]
    ) {
        let layout = new.config.layout
        func group(_ entries: [RoutineLogEntry]) -> [NoteID: [RoutineLogEntry]] {
            var out: [NoteID: [RoutineLogEntry]] = [:]
            for entry in entries {
                out[layout.routineLogPath(day: entry.day, device: entry.device), default: []]
                    .append(entry)
            }
            return out
        }
        let before = group(old.routineLog)
        let after = group(new.routineLog)

        for id in after.keys.sorted(by: { $0.path < $1.path }) {
            guard !owned.owns(id.path) else { continue }
            let entries = after[id] ?? []
            guard sorted(entries) != sorted(before[id] ?? []) else { continue }
            puts.append(.put(
                path: id.path, text: NoteCodec.encodeRoutineLog(entries, timeZone: timeZone)))
        }
    }

    private static func sorted(_ entries: [RoutineLogEntry]) -> [RoutineLogEntry] {
        entries.sorted { ($0.at, $0.routine, $0.step) < ($1.at, $1.routine, $1.step) }
    }

    // MARK: - The stale-write guard (N3)

    /// What every file `ops` would overwrite or move away from must still hold for the commit
    /// to be safe, keyed by path: the texts the file may hold, an empty list for "no file"
    /// (ARCHITECTURE §6, 2026-09-24). Two texts are acceptable for a note that came from a scan:
    /// its entity's encoding *and* the file text it was decoded from — they differ only when
    /// reading normalised something (an inbox capture without `created`), and that is not a
    /// change made elsewhere. Kept as text rather than a hash because a refusal shows the first
    /// one to the person as the base of the merge (2026-09-25).
    ///
    /// The expectation is the base snapshot's entity **encoded**: the codec patches the text it
    /// stashed at decode time, so an untouched entity encodes to its file byte for byte, and a
    /// queued command's base is the previous command's reduced entity, whose encoding is what
    /// that command wrote. A path the snapshot holds no note for must be **absent** — a file that
    /// appeared unseen is exactly the edit the guard exists to protect.
    ///
    /// Exempt: the routine log (one file per day per device — this device is its only writer,
    /// and log entries carry no passthrough to compare), `.moveFolder` (its files travel unread;
    /// nothing inside is overwritten) and move destinations (the store refuses to overwrite on a
    /// move). Paths are checked *before* the ops apply, so a rename's destination is expected
    /// absent even when the same command writes it right after the move.
    static func expectedContents(
        before ops: [VaultFileOp], in old: VaultSnapshot, timeZone: TimeZone = .current
    ) -> [String: [String]] {
        let routineLog = old.config.layout.routineLog + "/"
        var paths = Set<String>()
        for op in ops {
            switch op {
            case let .put(path, _), let .delete(path): paths.insert(path)
            case let .move(from, _): paths.insert(from)
            case .moveFolder, .createFolder: continue
            }
        }
        var expected: [String: [String]] = [:]
        for path in paths where !path.hasPrefix(routineLog) {
            expected[path] = acceptableTexts(at: path, in: old, timeZone: timeZone)
        }
        return expected
    }

    /// Every path the snapshot's note collections occupy — what a rename elsewhere can be found
    /// under (`VaultBackend.conflict(for:at:in:)`).
    static func entityPaths(in snapshot: VaultSnapshot) -> [String] {
        snapshot.inbox.map(\.id.path) + snapshot.actions.map(\.id.path)
            + snapshot.listItems.map(\.id.path) + snapshot.areas.map(\.id.path)
            + snapshot.projects.map(\.id.path) + snapshot.routines.map(\.id.path)
    }

    /// The file at `path` as `snapshot` knows it — its entity's encoding — or `nil` when the
    /// snapshot holds no note there.
    static func text(at path: String, in snapshot: VaultSnapshot, timeZone: TimeZone) -> String? {
        acceptableTexts(at: path, in: snapshot, timeZone: timeZone).first
    }

    /// The texts the file at `path` may hold according to `snapshot`: the entity's encoding
    /// first, then the text it was decoded from when that differs; empty when the snapshot
    /// holds no note there.
    static func acceptableTexts(
        at path: String, in snapshot: VaultSnapshot, timeZone: TimeZone
    ) -> [String] {
        let encoded: (text: String, passthrough: NotePassthrough)?
        if let item = snapshot.inbox.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(item, timeZone: timeZone), item.passthrough)
        } else if let action = snapshot.actions.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(action, timeZone: timeZone), action.passthrough)
        } else if let item = snapshot.listItems.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(item, timeZone: timeZone), item.passthrough)
        } else if let area = snapshot.areas.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(area), area.passthrough)
        } else if let project = snapshot.projects.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(project), project.passthrough)
        } else if let routine = snapshot.routines.first(where: { $0.id.path == path }) {
            encoded = (NoteCodec.encode(routine), routine.passthrough)
        } else if path == snapshot.config.layout.configFile {
            encoded = (NoteCodec.encode(snapshot.config), snapshot.config.passthrough)
        } else if let review = snapshot.lastReview,
                  review.noteID(layout: snapshot.config.layout).path == path {
            encoded = (NoteCodec.encode(review, timeZone: timeZone), review.passthrough)
        } else {
            encoded = nil
        }
        guard let encoded else { return [] }
        var texts = [encoded.text]
        if let source = NoteCodec.sourceText(of: encoded.passthrough), source != encoded.text {
            texts.append(source)
        }
        return texts
    }

    // MARK: - extraOps bookkeeping

    /// What `extraOps` speaks for: the paths it names, and the folders it moves.
    ///
    /// A `.moveFolder` (R-5) is the one op that owns paths it does not name — every note that
    /// travelled with the folder. Both ends count: a note under the old folder has *not* silently
    /// left the snapshot, and one under the new folder is the same note under a new path, never a
    /// new file to write from scratch.
    struct Ownership {
        private var paths: Set<String> = []
        private var folders: [(from: String, to: String)] = []
        /// destination → source, for the plain file moves.
        private var renamed: [String: String] = [:]

        init(_ ops: [VaultFileOp]) {
            for op in ops {
                switch op {
                case let .put(path, _):
                    paths.insert(path)
                case let .move(from, to):
                    paths.insert(from)
                    paths.insert(to)
                    renamed[to] = from
                case let .moveFolder(from, to):
                    folders.append((from: NoteID(path: from).path, to: NoteID(path: to).path))
                case .createFolder:
                    // An empty folder holds no note, so it speaks for no path.
                    continue
                case let .delete(path):
                    paths.insert(path)
                }
            }
        }

        /// True when `extraOps` has already said what happens to this path.
        func owns(_ path: String) -> Bool {
            if paths.contains(path) { return true }
            guard !folders.isEmpty else { return false }
            let id = NoteID(path: path)
            return folders.contains { id.isInside($0.from) || id.isInside($0.to) }
        }

        /// Where the note at `path` was before this command — `nil` when it is new.
        func source(of path: String) -> String? {
            if let source = renamed[path] { return source }
            let id = NoteID(path: path)
            guard let move = folders.first(where: { id.isInside($0.to) }) else { return nil }
            return move.from + id.path.dropFirst(move.to.count)
        }
    }

    /// Every path `extraOps` names outright. Folder moves name none — ``Ownership`` answers for
    /// those, and ``foldersMoved(in:)`` lists them.
    static func ownedPaths(in ops: [VaultFileOp]) -> Set<String> {
        var paths = Set<String>()
        for op in ops {
            switch op {
            case let .put(path, _): paths.insert(path)
            case let .move(from, to): paths.insert(from); paths.insert(to)
            case .moveFolder, .createFolder: continue
            case let .delete(path): paths.insert(path)
            }
        }
        return paths
    }

    /// The folder moves in `ops`, as (from, to) pairs. `VaultBackend` expands them into the files
    /// an undo would carry back, so a folder move can go stale like any other op.
    static func foldersMoved(in ops: [VaultFileOp]) -> [(from: String, to: String)] {
        ops.compactMap {
            guard case let .moveFolder(from, to) = $0 else { return nil }
            return (from: NoteID(path: from).path, to: NoteID(path: to).path)
        }
    }

    /// destination → source, for the moves in `extraOps`. A destination that turns up as a new
    /// entity is a rename, not a new note.
    static func moveDestinations(in ops: [VaultFileOp]) -> [String: String] {
        var map: [String: String] = [:]
        for case let .move(from, to) in ops { map[to] = from }
        return map
    }
}
