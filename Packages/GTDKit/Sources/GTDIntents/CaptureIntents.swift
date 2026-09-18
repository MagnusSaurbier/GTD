#if canImport(AppIntents)
import AppIntents
import Foundation
import GTDModel
import GTDVault

/// Background capture from a Shortcut, the Action Button or Siri (C1, C2).
/// **Owned by T30** — this is the compiling shell; it is not verified on Linux.
public struct CaptureToInboxIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture to inbox"
    public static let description = IntentDescription("Saves a note in the GTD inbox.")
    public static let openAppWhenRun = false

    @Parameter(title: "Text")
    public var text: String

    public init() {
        self.text = ""
    }

    public init(text: String) {
        self.text = text
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let request = CaptureRequest(text: text)
        _ = try request.perform(writer: InboxWriter())
        return .result(dialog: "Captured.")
    }
}

/// Opens the app at a routine runner (R3).
public struct StartRoutineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start routine"
    public static let openAppWhenRun = true

    @Parameter(title: "Routine")
    public var routine: String

    public init() {
        self.routine = ""
    }

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Opens inbox processing (I1).
public struct ProcessInboxIntent: AppIntent {
    public static let title: LocalizedStringResource = "Process inbox"
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}
#endif
