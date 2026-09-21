import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// State and mutations for the project detail view (P6): header, status, step checklist
/// (add/edit/check/reorder/promote), active actions, reference files, dated log.
/// Plain and unit-testable — **no SwiftUI**. Owned by T22.
@MainActor
@Observable
public final class ProjectDetailModel {
    public let projectID: NoteID

    private let model: AppModel

    public init(project: NoteID, model: AppModel) {
        self.projectID = project
        self.model = model
    }

    public var today: Day { model.today() }
    public var project: Project? { model.snapshot.project(projectID) }

    public var isStalled: Bool {
        guard let project else { return false }
        return Rules.isStalled(project, in: model.snapshot, today: today)
    }

    /// Active actions of the project (P6), most stable order first (same as `Rules.projectRows`).
    public var activeActions: [Action] {
        Rules.visibleActions(model.snapshot, today: today)
            .filter { $0.project == projectID && $0.status.countsTowardCap }
    }

    /// Dated log of completed actions, most recent first (P6).
    public var log: [LogEntry] {
        (project?.log ?? []).sorted { $0.day > $1.day }
    }

    /// Other files in the project folder, as `GTDVault` reports them (P6).
    public var referenceFiles: [String] { project?.referenceFiles ?? [] }

    public var steps: [ProjectStep] { project?.steps ?? [] }

    // MARK: - Header

    public func setOutcome(_ text: String) async throws {
        guard var project else { return }
        guard project.outcome != text else { return }
        project.outcome = text
        try await model.send(.updateProject(project))
    }

    public func setWhy(_ text: String) async throws {
        guard var project else { return }
        guard project.why != text else { return }
        project.why = text
        try await model.send(.updateProject(project))
    }

    // MARK: - Area (R-7)

    /// Every area the picker may offer, in vault order. "No area" is not one of them — it is the
    /// `nil` `area` of `setArea`, and it is offered without inventing a "No area" heading
    /// (STYLEGUIDE forbids one, ARCHITECTURE §6).
    public var areas: [Area] { model.snapshot.areas }

    public var area: Area? { project?.area.flatMap { model.snapshot.area($0) } }

    /// R-7/D42 — re-assigns the project's area. **This moves the project's folder** into the
    /// area's folder, or into `Projects/no_area/` when `area` is `nil`: one command, one commit,
    /// one undo. Every action linked to the project follows it and every note inside the folder
    /// travels with it, so the caller has nothing else to do.
    ///
    /// Refusals it can throw, both of which the picker shows rather than swallows:
    /// * `GTDError.titleCollision(<project name>)` — the destination already holds a project
    ///   (or a file) of that name; nothing was moved.
    /// * `GTDError.notFound(<area id>)` — the area is gone (another device removed it).
    ///
    /// Renaming a project is still refused; the folder name is its identity.
    public func setArea(_ area: NoteID?) async throws {
        guard var project, project.area != area else { return }
        project.area = area
        try await model.send(.updateProject(project))
    }

    // MARK: - Status

    /// How many Next actions leaving `active` would demote to Someday (P3) — shown before
    /// confirming, not gated behind a dialog (the change is undoable, N6).
    public func demotionCount(forChangingStatusTo newStatus: ProjectStatus) -> Int {
        guard let project, project.status == .active, newStatus != .active else { return 0 }
        return model.snapshot.actions.count { $0.project == projectID && $0.status.countsTowardCap }
    }

    @discardableResult
    public func setStatus(_ status: ProjectStatus) async throws -> Int {
        guard var project else { return 0 }
        let demoted = demotionCount(forChangingStatusTo: status)
        project.status = status
        try await model.send(.updateProject(project))
        return demoted
    }

    // MARK: - Steps: add / edit / check

    public func addStep(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var project else { return }
        project.steps.append(ProjectStep(text: trimmed))
        try await model.send(.updateProject(project))
    }

    public func editStep(at index: Int, text: String) async throws {
        guard var project, project.steps.indices.contains(index) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.steps[index].text = trimmed
        try await model.send(.updateProject(project))
    }

    public func toggleStep(at index: Int) async throws {
        guard var project, project.steps.indices.contains(index) else { return }
        project.steps[index].done.toggle()
        try await model.send(.updateProject(project))
    }

    // MARK: - Steps: reorder (drag + ⌥↑↓)

    public func moveStep(fromOffsets: IndexSet, toOffset: Int) async throws {
        guard var project else { return }
        project.steps = StepReorder.move(project.steps, fromOffsets: fromOffsets, toOffset: toOffset)
        try await model.send(.updateProject(project))
    }

    /// `⌥↑` on the step at `index`. No-op (no command sent) at the top boundary.
    public func moveStepUp(at index: Int) async throws {
        guard let project, let moved = StepReorder.moveUp(project.steps, at: index) else { return }
        var updated = project
        updated.steps = moved
        try await model.send(.updateProject(updated))
    }

    /// `⌥↓` on the step at `index`. No-op (no command sent) at the bottom boundary.
    public func moveStepDown(at index: Int) async throws {
        guard let project, let moved = StepReorder.moveDown(project.steps, at: index) else { return }
        var updated = project
        updated.steps = moved
        try await model.send(.updateProject(updated))
    }

    // MARK: - Steps: promote

    /// P6 — promotes an open step into a real action. Cap handling is simplified from T20's
    /// full "Next is full" sheet: the caller offers a single "Send to Someday instead" retry.
    @discardableResult
    public func promoteStep(at index: Int, draft: ActionDraft) async throws -> PromotionOutcome {
        try await sendCapAware(model, .promoteStep(project: projectID, stepIndex: index, draft))
    }

    @discardableResult
    public func promoteStepToSomeday(at index: Int, draft: ActionDraft) async throws -> PromotionOutcome {
        var somedayDraft = draft
        somedayDraft.status = .someday
        return try await promoteStep(at: index, draft: somedayDraft)
    }
}
