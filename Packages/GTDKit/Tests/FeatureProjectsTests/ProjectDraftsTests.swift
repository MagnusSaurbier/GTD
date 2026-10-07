import Testing
import Foundation
import GTDModel
import GTDAppCore
@testable import FeatureProjects

/// #94 — the project dialogs' drafts: when there is nothing to keep, and that they survive the
/// trip through `InputDrafts`.
@MainActor
struct ProjectDraftsTests {

    @Test func aNewProjectDraftIsEmptyOnlyWithNothingTypedOrChosen() {
        #expect(NewProjectDraft().isEmpty)
        #expect(NewProjectDraft(title: "  ").isEmpty)
        #expect(!NewProjectDraft(title: "Thesis").isEmpty)
        #expect(!NewProjectDraft(newAreaTitle: "Uni").isEmpty)
        #expect(!NewProjectDraft(area: NoteID(path: "Areas/Uni.md")).isEmpty)
    }

    @Test func theDraftsRoundTripThroughTheStore() {
        let drafts = InputDrafts()
        let project = NewProjectDraft(title: "Thesis", newAreaTitle: "", area: NoteID(path: "Areas/Uni.md"))
        drafts.keep(project, for: InputDraftKey.newProject)
        #expect(drafts.value(NewProjectDraft.self, for: InputDraftKey.newProject) == project)

        let convert = ConvertToProjectDraft(title: "Move flat", selectedStepIndex: 1)
        let key = InputDraftKey.convertToProject(NoteID(path: "Actions/Move.md"))
        drafts.keep(convert, for: key)
        #expect(drafts.value(ConvertToProjectDraft.self, for: key) == convert)
    }
}
