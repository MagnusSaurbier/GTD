import Foundation
import GTDModel

/// Pure editing operations on `GTDConfig.contexts` / `onTheGoContexts` (A4). No file access —
/// the result is sent through `GTDCommand.updateConfig` by `SettingsSession`. Kept separate from
/// SwiftUI so the impact computation (removing/renaming a context in use) is unit-testable.
public enum ContextsEditing {
    /// Actions whose `contexts` still reference `name` (A4: "removing a context in use shows the
    /// affected count and requires confirmation"). Renaming or removing a context only edits the
    /// config's list — existing action frontmatter is never rewritten silently ("no lying
    /// defaults"), so this count is shown as a warning, not auto-resolved.
    public static func affectedActionCount(for name: String, in actions: [Action]) -> Int {
        actions.reduce(0) { $0 + ($1.contexts.contains(name) ? 1 : 0) }
    }

    /// Adds a trimmed, non-empty, not-yet-present context to the end of the list.
    public static func adding(_ name: String, to config: GTDConfig) -> GTDConfig {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !config.contexts.contains(trimmed) else { return config }
        var next = config
        next.contexts.append(trimmed)
        return next
    }

    /// Renames `old` to `new` in both `contexts` and `onTheGoContexts`, keeping their order.
    /// No-op when `old` is unknown, `new` is empty/unchanged, or `new` already exists.
    public static func renaming(_ old: String, to new: String, in config: GTDConfig) -> GTDConfig {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, old != trimmed,
              config.contexts.contains(old), !config.contexts.contains(trimmed)
        else { return config }
        var next = config
        if let index = next.contexts.firstIndex(of: old) { next.contexts[index] = trimmed }
        if let index = next.onTheGoContexts.firstIndex(of: old) { next.onTheGoContexts[index] = trimmed }
        return next
    }

    /// Removes `name` from both lists. Existing actions keep the raw text (see above).
    public static func removing(_ name: String, from config: GTDConfig) -> GTDConfig {
        var next = config
        next.contexts.removeAll { $0 == name }
        next.onTheGoContexts.removeAll { $0 == name }
        return next
    }

    /// Reorders `contexts` the way `List.onMove` reports a drag (source offsets → destination
    /// index, both computed *before* the move — the same contract SwiftUI uses).
    public static func reordering(_ config: GTDConfig, from source: IndexSet, to destination: Int) -> GTDConfig {
        var next = config
        var items = next.contexts
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) { items.remove(at: index) }
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = max(0, min(destination - removedBefore, items.count))
        items.insert(contentsOf: moving, at: insertAt)
        next.contexts = items
        return next
    }

    /// Toggles membership in `onTheGoContexts` (A4's on-the-go subset). A context absent from
    /// `contexts` can never be added — it would be a lying default no chip could ever show.
    public static func togglingOnTheGo(_ name: String, in config: GTDConfig) -> GTDConfig {
        var next = config
        if let index = next.onTheGoContexts.firstIndex(of: name) {
            next.onTheGoContexts.remove(at: index)
        } else if next.contexts.contains(name) {
            next.onTheGoContexts.append(name)
        }
        return next
    }
}
