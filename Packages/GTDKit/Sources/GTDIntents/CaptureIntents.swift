#if canImport(AppIntents)
import AppIntents
import Foundation
import GTDModel
import GTDVault

/// Background capture from a Shortcut, the Action Button or Siri (C1, C2).
///
/// Runs with `openAppWhenRun = false`: `perform()` must not load or index the vault, only
/// resolve the bookmark and write one file through `InboxWriter` — that is what keeps capture
/// under three seconds with neither Obsidian nor the app running (C1). All the logic is in
/// `CaptureRequest`, which is Linux-testable with a fake writer; this file is the compiling shell
/// around it and is **unverified** until built on a Mac (T30 Result).
public struct CaptureToInboxIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture to Inbox"
    public static let description = IntentDescription("Saves a note in the GTD inbox. Works without opening the app.")
    public static let openAppWhenRun = false

    @Parameter(title: "Text", requestValueDialog: IntentDialog("What do you want to capture?"))
    public var text: String

    public init() {
        self.text = ""
    }

    public init(text: String) {
        self.text = text
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) to the GTD inbox")
    }

    /// `CaptureError` conforms to `LocalizedError`, so a thrown one surfaces its own
    /// `errorDescription` as the spoken/visible failure (empty text, no vault chosen, stale
    /// bookmark, or any other write failure) — T30 acceptance.
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try CaptureRequest(text: text).perform(writer: InboxWriter())
        return .result(dialog: "Captured.")
    }
}

/// Opens the app at a routine's step-by-step runner (R3).
///
/// `openAppWhenRun = true`: this genuinely needs the vault loaded (routine steps, today's log),
/// so unlike capture it is fine for this one to open the app. It cannot hand the app a
/// navigation target directly (no App Intents extension in this project — see
/// `PendingRoute`'s doc comment), so it leaves the routine's `gtd://routine/<id>` deep link as a
/// `PendingRoute` for T40 to consume on launch/foreground, the same way it already consumes one
/// from a notification tap.
public struct StartRoutineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Routine"
    public static let description = IntentDescription("Opens GTD at the chosen routine's runner.")
    public static let openAppWhenRun = true

    @Parameter(title: "Routine", requestValueDialog: IntentDialog("Which routine — Morning or Bedtime?"))
    public var routine: String

    public init() {
        self.routine = ""
    }

    public init(routine: String) {
        self.routine = routine
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$routine) routine")
    }

    public func perform() async throws -> some IntentResult {
        let title = routine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RoutineIntentError.noRoutineChosen }
        PendingRoute().set(RoutineDeepLink.url(forRoutineTitled: title))
        return .result()
    }
}

/// Opens the app at inbox processing (I1, part of C1's "capture then clear" loop).
public struct ProcessInboxIntent: AppIntent {
    public static let title: LocalizedStringResource = "Process Inbox"
    public static let description = IntentDescription("Opens GTD at inbox processing.")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        PendingRoute().set(InboxDeepLink.url)
        return .result()
    }
}

struct RoutineIntentError: LocalizedError {
    static let noRoutineChosen = RoutineIntentError(
        message: "No routine was given — say or type \"Morning\" or \"Bedtime\".")
    let message: String
    var errorDescription: String? { message }
}

/// Registers the three intents as Shortcuts/Siri phrases (T30 deliverable B).
public struct GTDAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureToInboxIntent(),
            phrases: [
                "Capture to \(.applicationName)",
                "Add to \(.applicationName) inbox",
                "Quick capture in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "tray.and.arrow.down.fill"
        )
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start my \(.applicationName) routine",
                "Start routine in \(.applicationName)"
            ],
            shortTitle: "Start Routine",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: ProcessInboxIntent(),
            phrases: [
                "Process my \(.applicationName) inbox",
                "Process \(.applicationName) inbox"
            ],
            shortTitle: "Process Inbox",
            systemImageName: "tray.full"
        )
    }
}
#endif
