import Foundation

/// The app's version as the shells stamp it in the bottom-right corner (`VersionStamp`) and as
/// Settings' About section prints it: `MARKETING_VERSION` from `project.yml`, which the ticket
/// rule ties to the issue that produced this build (`docs/TICKETS.md`: every `in progress` issue
/// claims the next `0.N`). Foundation-only so the wording is tested on Linux; the SwiftUI view
/// is a thin wrapper.
public struct AppVersion: Equatable, Sendable {
    /// `CFBundleShortVersionString`, e.g. `0.3`. Empty when the bundle carries none.
    public let short: String
    /// `CFBundleVersion`, e.g. `1`. Empty when the bundle carries none.
    public let build: String

    public init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    /// Reads the two keys from an `Info.plist` dictionary. A missing or non-string value reads
    /// as empty rather than as an invented "1.0" — a lying default is what STYLEGUIDE §1 forbids.
    public init(infoDictionary: [String: Any]?) {
        self.init(
            short: infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: infoDictionary?["CFBundleVersion"] as? String ?? "")
    }

    /// The running app's version.
    public static var current: AppVersion { AppVersion(infoDictionary: Bundle.main.infoDictionary) }

    /// What the corner stamp shows: the short version alone (`0.3`); the build number is
    /// Settings' business. Empty when the bundle carries no version, so the stamp draws nothing
    /// rather than a made-up number.
    public var stampLabel: String { short }

    /// Settings' About row: `0.3 (1)`, or just the part that is known.
    public var settingsLabel: String {
        switch (short.isEmpty, build.isEmpty) {
        case (false, false): return "\(short) (\(build))"
        case (false, true): return short
        case (true, false): return "(\(build))"
        case (true, true): return ""
        }
    }

    /// What VoiceOver says for the stamp: "Version 0.3".
    public var spokenLabel: String { Copy.version(short) }
}
