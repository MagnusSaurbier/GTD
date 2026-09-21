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
        diff(old.areas, new.areas, id: \.id) { NoteCodec.encode($0) }
        diff(old.projects, new.projects, id: \.id) { NoteCodec.encode($0) }
        diff(old.routines, new.routines, id: \.id) { NoteCodec.encode($0) }

        appendConfig(from: old, to: new, owned: owned, into: &puts)
        appendReview(from: old, to: new, owned: owned, timeZone: timeZone, into: &puts)
        appendRoutineLog(from: old, to: new, owned: owned, timeZone: timeZone, into: &puts)

        return extraOps + puts
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
            case .moveFolder: continue
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
