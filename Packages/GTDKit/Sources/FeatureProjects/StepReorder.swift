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

    /// Drag reorder via `List.onMove`: SwiftUI reports `destination` as the insertion index in
    /// the array **with the moved elements already removed**, which is exactly what
    /// `Array.move(fromOffsets:toOffset:)` expects (it is not a plain "insert before index").
    public static func move(_ steps: [ProjectStep], fromOffsets: IndexSet, toOffset: Int) -> [ProjectStep] {
        var copy = steps
        copy.move(fromOffsets: fromOffsets, toOffset: toOffset)
        return copy
    }
}
