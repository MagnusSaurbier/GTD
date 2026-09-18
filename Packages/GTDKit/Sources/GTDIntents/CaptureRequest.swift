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
    /// index the vault (C1: under 3 seconds, app not running). Failures are mapped to
    /// `CaptureError` so the intent can show a useful spoken/visible message (T30 acceptance).
    public func perform(writer: InboxWriter, now: Date = Date()) throws(CaptureError) -> NoteID {
        let text = try normalized()
        do {
            return try writer.capture(text: text, at: now)
        } catch let error as VaultError {
            throw CaptureError(vaultError: error)
        } catch {
            throw .writeFailed("\(error)")
        }
    }
}

public enum CaptureError: Error, Equatable, Sendable {
    case emptyText
    case noVaultSelected
    case bookmarkStale
    /// Any other `VaultError` (ioFailed, destinationExists, rollbackFailed…), carried as text —
    /// the intent surfaces it verbatim rather than pretending it knows the cause.
    case writeFailed(String)

    init(vaultError: VaultError) {
        switch vaultError {
        case .noVaultSelected: self = .noVaultSelected
        case .bookmarkStale: self = .bookmarkStale
        default: self = .writeFailed("\(vaultError)")
        }
    }
}

/// Spoken/visible text for `CaptureToInboxIntent`'s failure modes (T30 acceptance).
extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Nothing to capture — the text was empty."
        case .noVaultSelected:
            // GTDVault.VaultBookmark.startAccess() currently collapses "never picked" and
            // "picked but stale/corrupt" into the same failure (see InboxWriter.resolveFileSystem
            // / VaultBookmark.startAccess), so this message deliberately covers both rather than
            // claiming a precision `InboxWriter` cannot currently give (T30 Result: gotcha).
            return "No vault is available yet — open GTD once to pick or re-confirm your vault folder."
        case .bookmarkStale:
            return "The saved vault folder is no longer available. Open GTD to restore access."
        case .writeFailed(let reason):
            return "Could not save the capture: \(reason)"
        }
    }
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
