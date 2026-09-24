import Foundation

/// What can go wrong in the backend itself, as opposed to `GTDError` (the rules refused) and
/// `VaultError` (the file system refused).
///
/// Everything here is shown to the user by `AppModel.lastError`, so each case carries enough
/// to write a sentence about.
public enum ServiceError: Error, Equatable {
    /// `undo()` with an empty journal (N6). The UI should not offer undo in this state.
    case nothingToUndo

    /// The undo would overwrite a file that changed since the command ran — another device,
    /// Obsidian, or a sync landing late (N3). Undo is refused, never forced.
    case undoStale(path: String)

    /// A queued write was dropped because the one before it was refused: it was built on a
    /// state the vault never reached. Also what `undo()` answers when the thing it was meant to
    /// undo turned out not to have been saved.
    case writeDiscarded

    /// The command would overwrite or move a file that no longer holds what the snapshot it was
    /// reduced on says — another device, Obsidian or a sync landed in between (N3, ARCHITECTURE
    /// §6 2026-09-24). Refused, never merged: the vault is re-read and published, and the person
    /// makes the change again on the fresh note.
    case staleWrite(path: String)
}

extension ServiceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .nothingToUndo:
            "There is nothing to undo."
        case let .undoStale(path):
            "\(path) changed since then, so undoing would overwrite that change."
        case .writeDiscarded:
            "That change was not saved to the vault, so it has already been reverted."
        case let .staleWrite(path):
            "\(path) changed elsewhere since this device last read it. Reopen the note and make the change again."
        }
    }
}

/// Content hash used to notice that a file changed between a snapshot and the write built on it,
/// or between a command and its undo.
///
/// FNV-1a over the UTF-8 bytes plus the byte count. It is a *change detector*, not a security
/// primitive: CryptoKit does not exist on Linux, and a vault note is compared against a value
/// this same process wrote seconds earlier.
enum ContentHash {
    /// Marker for "no file at that path", so an absent file and an empty file differ.
    static let absent = "absent"

    static func of(_ text: String?) -> String {
        guard let text else { return absent }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var count = 0
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
            count += 1
        }
        return "\(String(hash, radix: 16))-\(count)"
    }
}
