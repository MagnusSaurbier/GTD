import Foundation
import GTDModel
import DesignSystem

/// Pure helpers for the Settings Lists section (L2, R-5, I4b). Creating/renaming/removing a
/// list moves a folder, so those go through `GTDCommand`/the reducer (`SettingsSession`) — this
/// only covers what stays entirely client-side: preparing the `favouriteLists` array a toggle or
/// a drag produces, and where the iPhone/Mac split falls in it. No file access.
public enum ListsEditing {
    /// `favouriteLists` is one synced list (R-5); the Mac shows more of it than the iPhone
    /// (`DesignSystem.NavbarPlatform`), so the stored array is capped at the **larger** of the
    /// two limits — the iPhone simply shows a prefix of it (`isShownOnPhone`).
    public static let storageLimit = NavbarPlatform.mac.favouriteLimit

    /// Refused client-side, before a command is even built — `GTDCommand.setFavouriteLists`
    /// itself has no count limit (only "every name must be a known list").
    public enum FavouriteError: Error, Sendable, Equatable {
        case limitReached(Int)
    }

    /// Adds `name` to `current` (the effective favourites — derived default or the stored
    /// choice, `SettingsSession.favouriteListNames`) or removes it if already present. Adding
    /// past `limit` is refused rather than silently dropping the oldest choice.
    public static func toggling(
        _ name: String, in current: [String], limit: Int = storageLimit
    ) throws(FavouriteError) -> [String] {
        if let index = current.firstIndex(where: { GTDList.sameName($0, name) }) {
            var next = current
            next.remove(at: index)
            return next
        }
        guard current.count < limit else { throw .limitReached(limit) }
        return current + [name]
    }

    /// Reorders `current` the way `List.onMove` reports a drag (source offsets → destination
    /// index, both computed *before* the move) — same contract as `ContextsEditing.reordering`.
    public static func reordering(
        _ current: [String], from source: IndexSet, to destination: Int
    ) -> [String] {
        var items = current
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) { items.remove(at: index) }
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = max(0, min(destination - removedBefore, items.count))
        items.insert(contentsOf: moving, at: insertAt)
        return items
    }

    /// Whether the favourite at `index` (0-based, in stored/shown order) is one of the slots the
    /// iPhone navbar actually shows (STYLEGUIDE §3.6 / `NavbarLayout`: four on iPhone, eight on
    /// Mac) — the rest are still stored, just Mac-only.
    public static func isShownOnPhone(index: Int) -> Bool {
        index < NavbarPlatform.iPhone.favouriteLimit
    }
}
