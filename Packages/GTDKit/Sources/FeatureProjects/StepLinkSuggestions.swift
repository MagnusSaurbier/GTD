import Foundation
import GTDModel

/// What the project detail's "New step" field suggests while the user types (#61): existing
/// action notes that could become a step of this project instead of a plain line of text.
/// Decided outside SwiftUI so it can be tested on Linux.
public enum StepLinkSuggestions {

    /// At most this many rows under the field — a hint, not a browser.
    public static let limit = 6

    /// Open actions whose title matches `query`, best match first.
    ///
    /// Offered: actions that are not done and belong to no project or to this one. An action of
    /// another project is left out (linking would silently take it away from there), and so is
    /// one a step of this project already points at. Matching ignores case and diacritics; a
    /// title that starts with the query ranks above one where a word starts with it, which ranks
    /// above a match inside a word. Ties keep alphabetical order.
    public static func matches(
        _ query: String, project projectID: NoteID, in snapshot: VaultSnapshot
    ) -> [Action] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        let linked = Set(snapshot.project(projectID)?.steps.compactMap(\.promotedTo) ?? [])

        let ranked: [(rank: Int, action: Action)] = snapshot.actions.compactMap { action in
            guard !action.status.isClosed,
                  action.project == nil || action.project == projectID,
                  !linked.contains(action.id),
                  let rank = rank(of: needle, in: fold(action.title))
            else { return nil }
            return (rank, action)
        }
        return ranked
            .sorted {
                $0.rank != $1.rank
                    ? $0.rank < $1.rank
                    : $0.action.title.localizedStandardCompare($1.action.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.action)
    }

    /// 0 = title prefix, 1 = word prefix, 2 = anywhere; `nil` = no match.
    static func rank(of needle: String, in title: String) -> Int? {
        guard let range = title.range(of: needle) else { return nil }
        if range.lowerBound == title.startIndex { return 0 }
        var search = title.startIndex..<title.endIndex
        while let hit = title.range(of: needle, range: search) {
            let before = title[title.index(before: hit.lowerBound)]
            if !before.isLetter && !before.isNumber { return 1 }
            search = title.index(after: hit.lowerBound)..<title.endIndex
        }
        return 2
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
