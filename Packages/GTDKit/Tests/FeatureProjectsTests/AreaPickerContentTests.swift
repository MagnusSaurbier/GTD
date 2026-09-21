import Testing
import Foundation
import GTDModel
import GTDFixtures
import DesignSystem
@testable import FeatureProjects

/// T11's project-detail area picker (P6, R-7): what the chip says, and how `setArea`'s two
/// refusals read — pinned here because the view cannot be compiled on Linux.
struct AreaPickerContentTests {

    @Test func aProjectWithAnAreaShowsItsTitleAsAConfirmedChip() {
        let chip = AreaPickerContent.chip(area: Fixtures.applicationsArea)
        #expect(chip.title == Fixtures.applicationsArea.title)
        #expect(chip.state == .confirmed)
    }

    /// No lying default, and never the forbidden "No area" label (STYLEGUIDE): unset is an
    /// outlined "Area" chip, the same shape as `ProjectPickerContent`'s unset "Project".
    @Test func noAreaIsAnUnsetChipNeverLabelledNoArea() {
        let chip = AreaPickerContent.chip(area: nil)
        #expect(chip.title == "Area")
        #expect(chip.state == .unset)
    }

    @Test func titleCollisionNamesTheProject() {
        #expect(AreaPickerContent.message(for: GTDError.titleCollision("DAAD")).contains("DAAD"))
    }

    @Test func notFoundSaysTheAreaIsGone() {
        #expect(AreaPickerContent.message(for: GTDError.notFound(Fixtures.applicationsArea.id)) == ProjectsCopy.areaGone)
    }
}
