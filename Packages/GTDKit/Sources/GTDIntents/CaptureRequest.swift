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

    /// Empty captures are rejected — there is nothing to name the note after (C3) — and
    /// leading/trailing whitespace is trimmed, line breaks kept.
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
        } catch InboxWriter.CaptureRefusal.empty {
            throw .emptyText
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
            // Since T41 `InboxWriter` resolves the bookmark before asking for access, so this
            // really does mean "no vault has ever been picked" — `.bookmarkStale` covers the
            // saved-but-unusable case separately.
            return "No vault is available yet — open GTD once to pick your vault folder."
        case .bookmarkStale:
            return "The saved vault folder is no longer available. Open GTD to restore access."
        case .writeFailed(let reason):
            return "Could not save the capture: \(reason)"
        }
    }
}
