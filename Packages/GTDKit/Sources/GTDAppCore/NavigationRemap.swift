import Foundation
import GTDModel

/// What a shell does to its navigation state when a new `SnapshotUpdate` arrives: **first**
/// follow the notes that were renamed, **then** drop the ones that are genuinely gone.
///
/// Both shells hold `NoteID`s — the iPhone a pushed path, the Mac a selected detail — and a
/// note's id is its file name (A1), so renaming it makes the old id disappear from the snapshot.
/// Pruning against the snapshot alone therefore cannot tell a rename from a deletion, and the
/// person editing a title loses the screen they are on. The order here is the fix, and the two
/// steps are one call so they cannot be applied in the wrong order or one without the other.
///
/// No SwiftUI, so both rules are unit-tested on Linux (ARCHITECTURE §5).
public enum NavigationRemap {

    /// A pushed path (iPhone). Entries are remapped through `renames`, then any entry `exists`
    /// rejects is removed; a remapped entry that would duplicate the one before it collapses,
    /// so renaming a note that is on the stack twice cannot produce two identical rows.
    public static func path(
        _ path: [NoteID], renames: RenameMap, exists: (NoteID) -> Bool
    ) -> [NoteID] {
        var result: [NoteID] = []
        for id in path {
            let current = renames.resolve(id)
            guard exists(current) else { continue }
            guard result.last != current else { continue }
            result.append(current)
        }
        return result
    }

    /// A single selection (the Mac's detail column, a running routine). `nil` when the note is
    /// gone for real.
    public static func selection(
        _ id: NoteID?, renames: RenameMap, exists: (NoteID) -> Bool
    ) -> NoteID? {
        guard let id else { return nil }
        let current = renames.resolve(id)
        return exists(current) ? current : nil
    }
}

public extension NavigationRemap {
    /// `path(_:renames:exists:)` against the actions of a snapshot — what both shells use for
    /// an action id.
    static func path(
        _ path: [NoteID], renames: RenameMap, in snapshot: VaultSnapshot
    ) -> [NoteID] {
        self.path(path, renames: renames) { snapshot.action($0) != nil }
    }
}
