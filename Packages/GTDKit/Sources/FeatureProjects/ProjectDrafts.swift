import Foundation
import GTDModel
import GTDAppCore

// #94 — what the project dialogs keep in `InputDrafts` while they are open. Neither the
// new-project sheet nor "Turn into project" has a note to write into before `Done`, and neither
// has a `Cancel`: every way out keeps the draft, `Done` clears it once the project exists.

/// The new-project sheet (E4): title, the area chosen or the new area typed.
public struct NewProjectDraft: Codable, Sendable, Equatable {
    public var title: String
    public var newAreaTitle: String
    public var area: NoteID?

    public init(title: String = "", newAreaTitle: String = "", area: NoteID? = nil) {
        self.title = title
        self.newAreaTitle = newAreaTitle
        self.area = area
    }

    /// Nothing typed or chosen.
    public var isEmpty: Bool {
        InputDrafts.isBlank(title) && InputDrafts.isBlank(newAreaTitle) && area == nil
    }
}

/// "Turn into project" (A2): the title as edited and the step chosen for promotion. The steps
/// themselves come from the action each time, so they are not kept.
public struct ConvertToProjectDraft: Codable, Sendable, Equatable {
    public var title: String
    public var selectedStepIndex: Int?

    public init(title: String, selectedStepIndex: Int?) {
        self.title = title
        self.selectedStepIndex = selectedStepIndex
    }
}
