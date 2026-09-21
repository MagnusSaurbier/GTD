import Testing
import Foundation
import GTDModel
import GTDFixtures
import DesignSystem
@testable import FeatureProjects

/// P6 (walkthrough 2026-09-19): the action detail's "Project" section was empty. The picker is a
/// chip now; what it says is pinned here because the view cannot be compiled on Linux.
struct ProjectPickerContentTests {
    private let snapshot = Fixtures.sampleSnapshot

    @Test func anActionWithAProjectShowsItsTitleAsAConfirmedChip() {
        let chip = ProjectPickerContent.chip(selection: Fixtures.daadProject.id, in: snapshot)
        #expect(chip.title == Fixtures.daadProject.title)
        #expect(chip.state == .confirmed)
    }

    /// No lying default: unset is an outlined "Project" chip — never "No project", and no literal
    /// "+" (the chip draws the plus symbol; P4).
    @Test func noProjectIsAnUnsetChipWithoutALiteralPlus() {
        let chip = ProjectPickerContent.chip(selection: nil, in: snapshot)
        #expect(chip.title == "Project")
        #expect(chip.state == .unset)
    }

    @Test func aDanglingProjectLinkStaysVisible() {
        let chip = ProjectPickerContent.chip(
            selection: NoteID(path: "Projects/Gone/Gone.md"), in: snapshot)
        #expect(chip.title == "Gone")
        #expect(chip.state == .confirmed)
    }

    @Test func theListOffersActiveProjectsPlusTheCurrentOne() throws {
        let inactive = try #require(snapshot.projects.first { $0.status != .active })
        let plain = ProjectPickerContent.options(selection: nil, in: snapshot)
        #expect(!plain.isEmpty)
        #expect(plain.allSatisfy { $0.status == .active })

        let withCurrent = ProjectPickerContent.options(selection: inactive.id, in: snapshot)
        #expect(withCurrent.contains { $0.id == inactive.id })
        #expect(withCurrent.count == plain.count + 1)
    }

    @Test func tappingTheSelectedRowClearsIt() {
        let a = Fixtures.daadProject.id
        let b = Fixtures.flatProject.id
        #expect(ProjectPickerContent.toggled(a, from: a) == nil)
        #expect(ProjectPickerContent.toggled(a, from: b) == a)
        #expect(ProjectPickerContent.toggled(a, from: nil) == a)
    }
}
