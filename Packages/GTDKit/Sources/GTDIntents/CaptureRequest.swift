import Foundation
import GTDModel
import GTDVault

/// The logic behind `CaptureToInboxIntent`, separated from the App Intents machinery so it can
/// be unit-tested on any platform (C1, C2). Owned by T30.
public struct CaptureRequest: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    /// Empty captures are rejected; leading/trailing whitespace is trimmed, line breaks kept.
    public func normalized() throws(CaptureError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyText }
        return trimmed
    }

    /// Writes the capture through `InboxWriter`. Needs only the bookmark — it must not load or
    /// index the vault (C1: under 3 seconds, app not running).
    public func perform(writer: InboxWriter, now: Date = Date()) throws -> NoteID {
        try writer.capture(text: try normalized(), at: now)
    }
}

public enum CaptureError: Error, Equatable {
    case emptyText
    case noVaultSelected
    case bookmarkStale
}

/// `yyyy-MM-dd HHmmss` — the capture file-name stamp (C3). Written by hand so the format is
/// identical on every platform and in every locale.
public enum CaptureStamp {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int = 2) -> String {
            let s = String(value ?? 0)
            return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
        }
        return "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day)) \(pad(c.hour))\(pad(c.minute))\(pad(c.second))"
    }
}
