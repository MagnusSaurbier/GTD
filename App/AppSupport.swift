import Foundation
import GTDModel
import DesignSystem

/// Launch arguments the shell understands.
enum LaunchOptions {
    /// `-useFixtures` runs the whole app on `InMemoryBackend` + `GTDFixtures.sampleSnapshot`:
    /// no bookmark, no file system, no notifications. UI tests and screenshots use it, and it is
    /// the only way to run the app without picking a vault first.
    static var useFixtures: Bool {
        ProcessInfo.processInfo.arguments.contains("-useFixtures")
    }
}

/// A stable, file-name-safe id for this device.
///
/// It ends up in `GTD/RoutineLog/<day>--<deviceID>.md` (N3: one file per device) and in the
/// reducer's `ReducerEnv`, so it must be stable across launches and contain nothing that would
/// upset a file name or another device's parser. Stored in `UserDefaults` — device-local state
/// never goes into the vault (ARCHITECTURE §3).
enum DeviceIdentity {
    static let defaultsKey = "gtd.deviceID"

    static let current: String = resolve(defaults: .standard)

    static func resolve(defaults: UserDefaults) -> String {
        if let saved = defaults.string(forKey: defaultsKey), !saved.isEmpty { return saved }
        let fresh = make()
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }

    /// The host name if it is usable, otherwise a short random id. Never empty.
    static func make(hostName: String = ProcessInfo.processInfo.hostName,
                     random: String = UUID().uuidString) -> String {
        let fromHost = sanitize(hostName.components(separatedBy: ".").first ?? hostName)
        if !fromHost.isEmpty { return String(fromHost.prefix(32)) }
        return "device-" + String(sanitize(random).prefix(8))
    }

    /// Letters, digits and `-`; everything else becomes `-`, runs collapse, edges trimmed.
    static func sanitize(_ raw: String) -> String {
        var out = ""
        for character in raw {
            if character.isLetter || character.isNumber {
                out.append(character)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }
}

/// Shell-level strings. Feature targets keep their own (`DesignSystem.Copy` is the shared set);
/// these are the ones only the app shell says. STYLEGUIDE §6.1: sentence case, verb-first
/// buttons, no exclamation marks, no praise.
enum AppCopy {
    static let openingVault = "Opening your vault"
    static let somethingWentWrong = "Something went wrong"
    static let ok = "OK"
    static let settings = "Settings"
    static let vaultIssues = "Vault issues"
    static let capture = "Capture"
    static let cancel = "Cancel"
    static let capturePlaceholder = "What's on your mind?"
    static let close = "Close"
    static let noVaultTitle = "No vault yet"
    static let noVaultBody = "Pick the Obsidian folder that contains Actions/."
    static let pickVault = "Choose folder…"
    static let routines = "Routines"
    static let projects = "Projects"
    static let deferred = "Deferred"
    static let goTo = "Go"

    /// Why the app could not open the saved vault folder, for the onboarding alert.
    static func vaultUnavailable(_ reason: String) -> String {
        "The saved vault folder could not be opened: \(reason)"
    }

    static func captureFailed(_ reason: String) -> String {
        "The capture could not be saved: \(reason)"
    }
}

/// SF Symbols only the shell needs (STYLEGUIDE §7 covers the concepts; these are chrome).
enum AppSymbols {
    static let vault = "folder"
    static let issues = "exclamationmark.triangle"
}

/// One error to show the person, with a stable identity so `.alert` can key on it.
struct AppError: Identifiable, Equatable {
    let id = UUID()
    var message: String

    init(message: String) {
        self.message = message
    }

    /// `CaptureError` carries its own wording (`LocalizedError`); `GTDError` gets the same
    /// wording the feature views use, so one refusal never reads two different ways. Anything
    /// else is described rather than hidden — a silent failure is a lying UI (§1).
    init(_ error: any Error) {
        switch error {
        case let GTDError.invalid(reason):
            self.message = reason
        case GTDError.nextCapReached:
            self.message = Copy.capSheetTitle
        case let GTDError.titleCollision(title):
            self.message = "Another note is already called \"\(title)\"."
        // R-3 — the shell's alert names the fields for every flow that is not a card
        // (docs/KNOWN_ISSUES.md).
        case let GTDError.missingFields(fields):
            self.message = Copy.missingFields(fields)
        case let GTDError.notFound(id):
            self.message = "\(id.path) is no longer in the vault."
        default:
            if let localized = error as? any LocalizedError, let description = localized.errorDescription {
                self.message = description
            } else {
                self.message = "\(error)"
            }
        }
    }
}
