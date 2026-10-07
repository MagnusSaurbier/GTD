import Testing
import Foundation
import GTDModel
@testable import FeatureProjects

struct SomedaySuggestionsTests {

    private let layout = VaultLayout.default

    private func action(
        _ title: String, _ status: ActionStatus = .someday, project: NoteID?, what: String = ""
    ) -> Action {
        Action(id: layout.actionPath(title: title), title: title, status: status, project: project, what: what)
    }

    private func project(_ title: String) -> Project {
        Project(id: layout.projectPath(title: title, inArea: nil), title: title, status: .active)
    }

    @Test func emptyQueryOffersTheWholeSomedayPileOfThisProjectOnly() {
        let here = project("GTD")
        let other = project("Thesis")
        let snapshot = VaultSnapshot(
            actions: [
                action("Weekly review sheet", project: here.id),
                action("Drag to category", project: here.id),
                action("Already next", .next, project: here.id),
                action("Done one", .done, project: here.id),
                action("Someday elsewhere", project: other.id),
                action("Someday loose", project: nil),
            ],
            projects: [here, other])
        #expect(SomedaySuggestions.matches(" ", project: here.id, in: snapshot).map(\.title)
                == ["Drag to category", "Weekly review sheet"])
    }

    @Test func everyWordMustMatchInAnyOrderBestRankFirst() {
        let here = project("GTD")
        let snapshot = VaultSnapshot(
            actions: [
                action("Brief an Prüfungsamt", project: here.id),
                action("Amtsbrief ablegen", project: here.id),
                action("Brief schreiben", project: here.id),
            ],
            projects: [here])
        #expect(SomedaySuggestions.matches("amt brief", project: here.id, in: snapshot).map(\.title)
                == ["Amtsbrief ablegen", "Brief an Prüfungsamt"])
        #expect(SomedaySuggestions.matches("PRUF", project: here.id, in: snapshot).map(\.title)
                == ["Brief an Prüfungsamt"])
    }

    @Test func aMatchOnlyInWhatComesAfterTitleMatches() {
        let here = project("GTD")
        let snapshot = VaultSnapshot(
            actions: [
                action("Sync settings", project: here.id, what: "iCloud key-value store"),
                action("iCloud conflict sheet", project: here.id),
            ],
            projects: [here])
        #expect(SomedaySuggestions.matches("icloud", project: here.id, in: snapshot).map(\.title)
                == ["iCloud conflict sheet", "Sync settings"])
    }
}
