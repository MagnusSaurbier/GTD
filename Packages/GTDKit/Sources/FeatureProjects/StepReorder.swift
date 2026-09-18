import Foundation
import GTDModel

/// Index maths for reordering a project's step checklist (P6: drag + `⌥↑↓`). Pure and
/// Linux-testable — no SwiftUI, no `AppModel`. Callers write the returned array back with
/// `.updateProject`; the reducer does not know about step order beyond array position.
public enum StepReorder {

    /// Moves the step at `source` to `destination`, clamping `destination` into bounds and
    /// treating a same-place move as a no-op. Matches `Array.move(fromOffsets:toOffset:)`
    /// semantics for a single source index: `destination` is the index the item should occupy
    /// **after** it is removed from `source`.
    public static func move(_ steps: [ProjectStep], from source: Int, to destination: Int) -> [ProjectStep] {
        guard steps.indices.contains(source), steps.count > 1 else { return steps }
        let clamped = max(0, min(destination, steps.count - 1))
        guard clamped != source else { return steps }
        var copy = steps
        let item = copy.remove(at: source)
        copy.insert(item, at: clamped)
        return copy
    }

    /// `⌥↑` — one step earlier. `nil` at the top boundary or an out-of-range index: no state change.
    public static func moveUp(_ steps: [ProjectStep], at index: Int) -> [ProjectStep]? {
        guard steps.indices.contains(index), index > 0 else { return nil }
        return move(steps, from: index, to: index - 1)
    }

    /// `⌥↓` — one step later. `nil` at the bottom boundary or an out-of-range index: no state change.
    public static func moveDown(_ steps: [ProjectStep], at index: Int) -> [ProjectStep]? {
        guard steps.indices.contains(index), index < steps.count - 1 else { return nil }
        return move(steps, from: index, to: index + 1)
    }

    /// Drag reorder via `List.onMove`. Reimplements `Array.move(fromOffsets:toOffset:)`'s exact
    /// semantics by hand: that convenience lives in SwiftUI, which this file cannot import (it
    /// must stay Linux-testable — ARCHITECTURE §5). `destination` is the insertion index SwiftUI
    /// reports, computed **after** the moved elements are removed.
    public static func move(_ steps: [ProjectStep], fromOffsets source: IndexSet, toOffset destination: Int) -> [ProjectStep] {
        let validSource = source.filter { steps.indices.contains($0) }
        guard !validSource.isEmpty else { return steps }
        let itemsToMove = validSource.map { steps[$0] }

        var copy = steps
        for index in validSource.sorted(by: >) {
            copy.remove(at: index)
        }
        let adjustedDestination = destination - validSource.count { $0 < destination }
        let clamped = max(0, min(adjustedDestination, copy.count))
        copy.insert(contentsOf: itemsToMove, at: clamped)
        return copy
    }
}
