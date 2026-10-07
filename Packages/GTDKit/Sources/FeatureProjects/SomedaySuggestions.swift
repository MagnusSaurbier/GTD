import Foundation
import GTDModel

/// What "What's next?" offers from the project's own Someday pile (#84): the project's Someday
/// actions, narrowed while the user types into the New action field. Picking one moves that
/// note into Next instead of writing a new one. Decided outside SwiftUI so it can be tested on
/// Linux.
public enum SomedaySuggestions {

    /// The project's Someday actions matching `query`, best match first.
    ///
    /// An empty query offers all of them, alphabetical. Otherwise every word of the query has
    /// to occur in the title (in any order, so "brief amt" finds "Brief an Prüfungsamt"), ignoring
    /// case and diacritics. A word starting the title ranks above one starting a word, which
    /// ranks above one inside a word (`StepLinkSuggestions.rank`); an action whose title misses a
    /// word but whose `What?` has all of them still shows, below every title match. Ties keep
    /// alphabetical order.
    public static func matches(
        _ query: String, project projectID: NoteID, in snapshot: VaultSnapshot
    ) -> [Action] {
        let words = StepLinkSuggestions.fold(query)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let pile = snapshot.actions.filter { $0.project == projectID && $0.status == .someday }

        let ranked: [(rank: Int, action: Action)] = pile.compactMap { action in
            guard !words.isEmpty else { return (0, action) }
            if let rank = rank(of: words, in: StepLinkSuggestions.fold(action.title)) {
                return (rank, action)
            }
            let what = StepLinkSuggestions.fold(action.title + " " + action.what)
            guard rank(of: words, in: what) != nil else { return nil }
            return (Int.max, action)
        }
        return ranked
            .sorted {
                $0.rank != $1.rank
                    ? $0.rank < $1.rank
                    : $0.action.title.localizedStandardCompare($1.action.title) == .orderedAscending
            }
            .map(\.action)
    }

    /// Sum of the words' ranks; `nil` when one of them does not occur.
    static func rank(of words: [String], in text: String) -> Int? {
        var total = 0
        for word in words {
            guard let rank = StepLinkSuggestions.rank(of: word, in: text) else { return nil }
            total += rank
        }
        return total
    }
}
