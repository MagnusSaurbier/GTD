import Testing
import Foundation
import GTDModel
@testable import FeatureProjects

struct StepLinkSuggestionsTests {

    private let layout = VaultLayout.default

    private func action(_ title: String, _ status: ActionStatus = .someday, project: NoteID? = nil) -> Action {
        Action(id: layout.actionPath(title: title), title: title, status: status, project: project)
    }

    private func project(_ title: String, steps: [ProjectStep] = []) -> Project {
        Project(id: layout.projectPath(title: title, inArea: nil), title: title, status: .active, steps: steps)
    }

    @Test func emptyQueryOffersNothing() {
        let here = project("DAAD")
        let snapshot = VaultSnapshot(actions: [action("Write letter")], projects: [here])
        #expect(StepLinkSuggestions.matches("  ", project: here.id, in: snapshot).isEmpty)
    }

    @Test func ranksTitlePrefixThenWordPrefixThenInside() {
        let here = project("DAAD")
        let snapshot = VaultSnapshot(
            actions: [action("Unterbrief"), action("Brief an Prüfungsamt"), action("Den Brief schreiben")],
            projects: [here])
        #expect(StepLinkSuggestions.matches("brief", project: here.id, in: snapshot).map(\.title)
                == ["Brief an Prüfungsamt", "Den Brief schreiben", "Unterbrief"])
    }

    @Test func ignoresCaseAndDiacritics() {
        let here = project("DAAD")
        let snapshot = VaultSnapshot(actions: [action("Prüfungsamt anrufen")], projects: [here])
        #expect(StepLinkSuggestions.matches("PRUF", project: here.id, in: snapshot).map(\.title)
                == ["Prüfungsamt anrufen"])
    }

    @Test func leavesOutDoneForeignAndAlreadyLinkedActions() {
        let other = project("Nebenjob")
        let linked = action("Letter linked")
        let here = project("DAAD", steps: [ProjectStep(text: "Letter linked", promotedTo: linked.id)])
        let snapshot = VaultSnapshot(
            actions: [
                action("Letter done", .done),
                action("Letter elsewhere", project: other.id),
                linked,
                action("Letter loose"),
                action("Letter here", .next, project: here.id),
            ],
            projects: [here, other])
        #expect(StepLinkSuggestions.matches("letter", project: here.id, in: snapshot).map(\.title)
                == ["Letter here", "Letter loose"])
    }

    @Test func capsTheList() {
        let here = project("DAAD")
        let snapshot = VaultSnapshot(actions: (0..<10).map { action("Task \($0)") }, projects: [here])
        #expect(StepLinkSuggestions.matches("task", project: here.id, in: snapshot).count
                == StepLinkSuggestions.limit)
    }
}
