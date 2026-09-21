import Foundation
import GTDModel
import GTDAppCore

/// The result of a promotion, with the two refusals a promotion can *answer* rather than only
/// report: the Next cap (I4, A3) and the fields Next demands (R-3, D12).
///
/// Every promotion path in this target (`ProjectDetailModel`, `WhatsNextModel`,
/// `ConvertToProjectModel`) returns this instead of throwing, so the view can offer the same
/// simplified fallback for both — "send it to Someday instead" — without re-deriving the reason
/// from the error by hand. Someday always works: a promoted step's `What?` is the step line
/// itself (ARCHITECTURE §6, T04-1).
public enum PromotionOutcome: Sendable, Equatable {
    case success
    case capReached(cap: Int)
    /// R-3 — a one-tap promotion into Next has no `Why?`, no context and no time estimate. The
    /// user fills them in (the project detail's promote form has all three) or takes Someday.
    case missingFields([RequiredField])
}

/// Runs `command`, turning the two answerable refusals into an outcome and rethrowing anything
/// else. Shared by every model in this target that promotes something into Next.
@MainActor
func sendCapAware(_ model: AppModel, _ command: GTDCommand) async throws -> PromotionOutcome {
    do {
        try await model.send(command)
        return .success
    } catch let error as GTDError {
        switch error {
        case let .nextCapReached(cap): return .capReached(cap: cap)
        case let .missingFields(fields): return .missingFields(fields)
        default: throw error
        }
    }
}
