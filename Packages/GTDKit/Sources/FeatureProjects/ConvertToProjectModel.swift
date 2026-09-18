import Foundation
import Observation
import GTDModel
import GTDAppCore

/// State and actions behind `ConvertToProjectSheet` (A2): an action with ≥ 2 checkboxes becomes
/// a project, its checkboxes become steps, title/why carry over, and the first step starts
/// pre-selected for immediate promotion. Plain and unit-testable — **no SwiftUI**. Owned by T22.
@MainActor
@Observable
public final class ConvertToProjectModel {
    public let actionID: NoteID

    private let model: AppModel

    public init(action: NoteID, model: AppModel) {
        self.actionID = action
        self.model = model
    }

    public var action: Action? { model.snapshot.action(actionID) }

    /// The checkboxes that become steps (A2), in file order.
    public var suggestedSteps: [String] { action?.checkboxes.map(\.text) ?? [] }

    /// A draft seeded from the action: title and why carried over, steps from its checkboxes.
    /// The caller edits this (title, steps) before calling `convert`.
    public func makeDraft() -> ProjectDraft {
        guard let action else { return ProjectDraft(title: "") }
        return ProjectDraft(title: action.title, why: action.why, steps: suggestedSteps)
    }

    /// The new project's note id, computed the same way the reducer will — so the caller can
    /// promote the pre-selected step right after conversion, in the same flow, without a
    /// round trip through the snapshot to find the project it just created.
    public func projectID(for draft: ProjectDraft) -> NoteID {
        var areaID = draft.area
        if let newAreaTitle = draft.newAreaTitle,
           !newAreaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            areaID = model.snapshot.config.layout.areaPath(title: newAreaTitle)
        }
        return model.snapshot.config.layout.projectPath(title: draft.title, inArea: areaID)
    }

    /// Converts the action, then — when `promoteStepIndex` names a step in `draft.steps` —
    /// promotes it in the same flow (the brief's "first step pre-selected for promotion").
    /// Cap handling is simplified from T20: the caller offers a single "Send to Backlog instead".
    @discardableResult
    public func convert(_ draft: ProjectDraft, promoteStepIndex: Int?) async throws -> PromotionOutcome {
        try await model.send(.convertActionToProject(actionID, draft))
        guard let promoteStepIndex, draft.steps.indices.contains(promoteStepIndex) else { return .success }
        let newProject = projectID(for: draft)
        let promoteDraft = ActionDraft(title: draft.steps[promoteStepIndex], status: .next)
        return try await sendCapAware(
            model, .promoteStep(project: newProject, stepIndex: promoteStepIndex, promoteDraft))
    }

    /// Cap fallback for the step promoted right after conversion (the project itself is
    /// already created at this point — only the promotion is retried, to Backlog).
    @discardableResult
    public func promoteConvertedStepToBacklog(_ draft: ProjectDraft, stepIndex: Int) async throws -> PromotionOutcome {
        let newProject = projectID(for: draft)
        let promoteDraft = ActionDraft(title: draft.steps[stepIndex], status: .backlog)
        return try await sendCapAware(model, .promoteStep(project: newProject, stepIndex: stepIndex, promoteDraft))
    }
}
