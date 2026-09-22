import Foundation

/// The notes one snapshot update moved from one `NoteID` to another — a rename, not a deletion.
///
/// A note's identity **is** its path (`Actions/<Title>.md`, A1), so renaming an action produces a
/// snapshot in which the old id is gone and a new one appeared. Nothing in the snapshot itself
/// says the two are the same note, which is why the `Reduction` that produced them carries this
/// map alongside: anything holding a `NoteID` — a pushed navigation path, a window's selection —
/// can follow the note instead of concluding it was deleted.
///
/// Empty for every command that renames nothing, which is almost all of them.
public struct RenameMap: Sendable, Equatable {

    /// old id → new id. Never contains an identity pair.
    private var moves: [NoteID: NoteID]

    public static let empty = RenameMap()

    public init() { moves = [:] }

    public init(_ moves: [NoteID: NoteID]) {
        self.moves = moves.filter { $0.key != $0.value }
    }

    public init(from old: NoteID, to new: NoteID) {
        self.init([old: new])
    }

    public var isEmpty: Bool { moves.isEmpty }

    /// The pairs, sorted by old id — for tests and for anything that wants to show them.
    public var pairs: [(old: NoteID, new: NoteID)] {
        moves.sorted { $0.key < $1.key }.map { (old: $0.key, new: $0.value) }
    }

    /// The way back: every new id → the id it had. What a backend publishes when it has to take
    /// a rename back, so navigation follows the note home instead of losing it.
    public var inverted: RenameMap {
        RenameMap(Dictionary(moves.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first }))
    }

    public mutating func record(_ old: NoteID, as new: NoteID) {
        guard old != new else { return }
        self = merging(RenameMap([old: new]))
    }

    /// Where `id` ended up, or `id` itself when this map says nothing about it.
    ///
    /// Follows a chain (A → B → C) so a map that accumulated two renames of the same note still
    /// answers with the note's current id. Bounded by the number of entries, so a cycle a
    /// hand-built map could contain cannot spin.
    public func resolve(_ id: NoteID) -> NoteID {
        var current = id
        for _ in 0..<moves.count {
            guard let next = moves[current], next != current else { return current }
            current = next
        }
        return current
    }

    /// This map followed by `later`: a note renamed A → B here and B → C there is A → C.
    ///
    /// That is what lets a consumer batch updates — two renames that arrive before it looks
    /// compose into one, instead of the second being lost.
    public func merging(_ later: RenameMap) -> RenameMap {
        guard !later.isEmpty else { return self }
        var result: [NoteID: NoteID] = [:]
        for (old, new) in moves {
            result[old] = later.moves[new] ?? new
        }
        for (old, new) in later.moves where result[old] == nil {
            result[old] = new
        }
        return RenameMap(result)
    }
}
