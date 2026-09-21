import Foundation
import GTDModel
import GTDAppCore

/// The result of any command that can be refused by the Next cap (I4, A3). Every promotion path
/// in this target (`ProjectDetailModel`, `WhatsNextModel`, `ConvertToProjectModel`) returns this
/// instead of throwing on `GTDError.nextCapReached`, so the view can offer the simplified
/// fallback from the brief ("cap error handled like in T20 but simplified: offer Someday")
/// without re-deriving the cap from the error by hand.
public enum PromotionOutcome: Sendable, Equatable {
    case success
    case capReached(cap: Int)
}

/// Runs `command`, turning a refused-by-cap error into `.capReached` and rethrowing anything else.
/// Shared by every model in this target that can hit the cap.
@MainActor
func sendCapAware(_ model: AppModel, _ command: GTDCommand) async throws -> PromotionOutcome {
    do {
        try await model.send(command)
        return .success
    } catch let error as GTDError {
        if case let .nextCapReached(cap) = error { return .capReached(cap: cap) }
        throw error
    }
}
