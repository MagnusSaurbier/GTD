import Testing
import Foundation
import GTDModel
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// What the keyboard walk stands on in each sheet of the Mac inbox flow (#77), in the order the
/// sheet draws it.
struct SheetWalksTests {

    @Test func theProjectPickerWalksClearProjectsThenCreate() {
        let snapshot = Fixtures.sampleSnapshot
        let all = ProjectPicker.model(snapshot, search: "")
        let ids = all.groups.flatMap(\.projects).map(\.id)
        #expect(!ids.isEmpty)
        #expect(all.walkRows(canClear: false) == [ids.map(ProjectPickStop.project)])
        #expect(all.walkRows(canClear: true).first?.first == .clear)

        let typed = ProjectPicker.model(snapshot, search: "Zzz new thing")
        #expect(typed.walkRows(canClear: false) == [[.create("Zzz new thing")]],
                "nothing matches: only the create row")
    }

    @Test func theListPickerWalksTheListsThenNewList() {
        #expect(ListPickStop.walkRows(lists: ["Read", "Watch"], isAddingList: false)
            == [[.list("Read"), .list("Watch"), .newList]])
        #expect(ListPickStop.walkRows(lists: ["Read"], isAddingList: true) == [[.list("Read")]],
                "while the name field is open it has the keys")
        #expect(ListPickStop.walkRows(lists: [], isAddingList: false) == [[.newList]],
                "the empty state's New list… is walkable too")
    }

    @Test func theKnowledgeSheetWalksSuggestionFoldersProjectsDone() {
        let tree = KnowledgeTree.build(["Cooking", "Tech/Swift", "Tech/Rust"])
        let project = NoteID(path: "Projects/X/X.md")
        let closed = KnowledgePickStop.walkRows(
            suggestion: "Tech/Swift", tree: tree, expanded: [], projects: [project],
            isAddingFolder: false)
        #expect(closed == [[KnowledgePickStop]]([
            [.suggestion("Tech/Swift")],
            [.folder(""), .folder("Cooking"), .folder("Tech"), .newFolder],
            [.project(project)],
            [.done],
        ]))

        let open = KnowledgePickStop.walkRows(
            suggestion: nil, tree: tree, expanded: ["Tech"], projects: [],
            isAddingFolder: true)
        #expect(open[0].isEmpty)
        #expect(open[1] == [.folder(""), .folder("Cooking"), .folder("Tech"),
                            .folder("Tech/Rust"), .folder("Tech/Swift")],
                "an open folder shows its children under it; New folder gives way to its field")
        #expect(KeyWalk.first(in: open.map(\.count)) == KeyWalk(row: 1),
                "no suggestion: the walk starts on the root folder")
    }

    @Test func deferToReviewWalksDeferThenCancel() {
        #expect(DeferReviewStop.walkRows == [[.deferIt, .cancel]])
    }
}
