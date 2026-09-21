import Foundation
import Observation
import GTDModel
import GTDAppCore

/// State and actions behind `WhatsNextSheet` (P5): one-tap promotion of a remaining step, a
/// free-text new action, "nothing yet", "project is done". Plain and unit-testable —
/// **no SwiftUI**. Owned by T22.
@MainActor
@Observable
public final class WhatsNextModel {
    public let projectID: NoteID

    private let model: AppModel

    public init(project: NoteID, model: AppModel) {
        self.projectID = project
        self.model = model
    }

    public var project: Project? { model.snapshot.project(projectID) }
    public var title: String { project?.title ?? "" }

    /// One remaining step, paired with its index in the project's full `steps` array —
    /// `promote(stepIndex:)` takes that same index, matching `GTDCommand.promoteStep`'s
    /// indexing exactly (`ProjectStep` carries no id of its own).
    public struct OpenStep: Sendable, Equatable, Identifiable {
        public var stepIndex: Int
        public var step: ProjectStep
        public var id: Int { stepIndex }
    }

    /// Remaining steps offered for one-tap promotion (P5).
    public var openSteps: [OpenStep] {
        guard let project else { return [] }
        return project.steps.enumerated()
            .filter { !$0.element.done && $0.element.promotedTo == nil }
            .map { OpenStep(stepIndex: $0.offset, step: $0.element) }
    }

    /// True once this project has no open action left — "nothing yet" leaves it this way,
    /// and the sheet says so (STYLEGUIDE `stalledProjectBody`).
    public var isStalled: Bool {
        guard let project else { return false }
        return Rules.isStalled(project, in: model.snapshot, today: model.today())
    }

    /// Promotes the step at `stepIndex` (an index into the project's full `steps` array — see
    /// `openSteps`) into a **Next** action.
    ///
    /// R-3 — Next asks for `Why?`, a context and a time estimate, which a step line does not
    /// carry: pass the `fields` the sheet collected, or take the `.missingFields` answer and
    /// offer Someday (`promoteToSomeday`), which always works because the step line is the
    /// `What?` (ARCHITECTURE §6, T04-1).
    @discardableResult
    public func promote(stepIndex: Int, fields: ActionDraft? = nil) async throws -> PromotionOutcome {
        try await promote(stepIndex: stepIndex, status: .next, fields: fields)
    }

    @discardableResult
    public func promoteToSomeday(stepIndex: Int, fields: ActionDraft? = nil) async throws -> PromotionOutcome {
        try await promote(stepIndex: stepIndex, status: .someday, fields: fields)
    }

    private func promote(
        stepIndex: Int, status: ActionStatus, fields: ActionDraft?
    ) async throws -> PromotionOutcome {
        guard let project, project.steps.indices.contains(stepIndex) else { return .success }
        var draft = fields ?? ActionDraft(title: project.steps[stepIndex].text)
        draft.title = project.steps[stepIndex].text
        draft.status = status
        return try await sendCapAware(model, .promoteStep(project: projectID, stepIndex: stepIndex, draft))
    }

    /// Free-text new action, not tied to an existing step (P5). The typed line is both the
    /// title and the `What?`; `fields` carries whatever else Next requires (R-3).
    @discardableResult
    public func createAction(title: String, fields: ActionDraft? = nil) async throws -> PromotionOutcome {
        try await createAction(title: title, status: .next, fields: fields)
    }

    @discardableResult
    public func createActionInSomeday(title: String, fields: ActionDraft? = nil) async throws -> PromotionOutcome {
        try await createAction(title: title, status: .someday, fields: fields)
    }

    private func createAction(
        title: String, status: ActionStatus, fields: ActionDraft?
    ) async throws -> PromotionOutcome {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success }
        var draft = fields ?? ActionDraft(title: trimmed)
        draft.title = trimmed
        draft.status = status
        draft.project = projectID
        if draft.what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.what = trimmed }
        return try await sendCapAware(model, .createAction(draft))
    }

    /// "Project is done" (P5).
    public func markDone() async throws {
        guard var project else { return }
        project.status = .done
        try await model.send(.updateProject(project))
    }
}
