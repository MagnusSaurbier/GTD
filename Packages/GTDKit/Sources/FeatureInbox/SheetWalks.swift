import Foundation
import GTDModel
import DesignSystem

// What the keyboard walk (#77) stands on in each sheet of the Mac inbox flow, row by row, in the
// order the sheet draws it. The sheets keep a `KeyWalk` and ask these for the stop under it;
// pressing a stop does exactly what a click on it does. Pure, so the stop lists are tested on
// Linux (`SheetWalksTests`).

/// The project picker — the card's `+ project` chip, the date row's and the outcome row's
/// `Project`, and a drop onto a project (`ProjectChoiceSheet`). One row: `Clear project` when
/// there is something to clear, the projects in the order the (filtered) tree lists them, then
/// `Create project "<text>"` when offered.
public enum ProjectPickStop: Sendable, Equatable, Hashable {
    case clear
    case project(NoteID)
    case create(String)
}

public extension ProjectPickerModel {
    func walkRows(canClear: Bool) -> [[ProjectPickStop]] {
        var stops: [ProjectPickStop] = canClear ? [.clear] : []
        stops += groups.flatMap(\.projects).map { .project($0.id) }
        if let createTitle { stops.append(.create(createTitle)) }
        return [stops]
    }
}

/// The list picker — the navbar's `More…`, and a drop onto Lists (`ListChoiceSheet`). One row:
/// every list, then `New list…` (left out while its name field is open — the field has the keys).
public enum ListPickStop: Sendable, Equatable, Hashable {
    case list(String)
    case newList

    public static func walkRows(lists: [String], isAddingList: Bool) -> [[ListPickStop]] {
        [lists.map(ListPickStop.list) + (isAddingList ? [] : [.newList])]
    }
}

/// The Knowledge sheet: the suggested folder, the folder tree as far as it is open (the root
/// `Knowledge` first, `New folder` last), the projects, and `Done`.
public enum KnowledgePickStop: Sendable, Equatable, Hashable {
    case suggestion(String)
    /// A folder path; `""` is the root `Knowledge` folder.
    case folder(String)
    case newFolder
    case project(NoteID)
    case done

    public static func walkRows(
        suggestion: String?, tree: [FolderNode], expanded: Set<String>,
        projects: [NoteID], isAddingFolder: Bool
    ) -> [[KnowledgePickStop]] {
        [
            suggestion.map { [.suggestion($0)] } ?? [],
            [.folder("")] + KnowledgeTree.visible(tree, expanded: expanded).map { .folder($0.path) }
                + (isAddingFolder ? [] : [.newFolder]),
            projects.map(KnowledgePickStop.project),
            [.done],
        ]
    }
}

public extension KnowledgeTree {
    /// The folders a tree shows with `expanded` open, depth-first — the rows under the root.
    static func visible(_ nodes: [FolderNode], expanded: Set<String>) -> [FolderNode] {
        nodes.flatMap { node in
            [node] + (expanded.contains(node.path) ? visible(node.children, expanded: expanded) : [])
        }
    }
}

/// `Defer to review`: after the reason, one row — `Defer`, `Cancel`.
public enum DeferReviewStop: Sendable, Equatable, Hashable, CaseIterable {
    case deferIt
    case cancel

    public static let walkRows: [[DeferReviewStop]] = [allCases]
}
