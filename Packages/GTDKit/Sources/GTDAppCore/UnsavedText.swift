import Foundation
import Observation
import GTDModel

/// Text typed into an editor that had not reached the vault yet (#56).
///
/// The editors hold typed text until a natural moment — blur, closing the detail, leaving the
/// foreground, ⌘Q (`AppModel.HeldEdits`). A crash skips every one of those, and on 2026-09-28
/// that lost a note body the person had just written. So each held edit is also copied into a
/// small journal on this device, outside the vault, and a launch that finds an entry there
/// offers it back (`UnsavedTextJournal.recovered`). The journal never writes the vault on its
/// own: restoring is a command the person chooses, like any other edit.
public struct UnsavedText: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case action
        case listItem
    }

    public var kind: Kind
    /// Where the note was when the text was typed.
    public var path: String
    /// The typed title, when the title was among the unsaved fields.
    public var title: String?
    /// The typed body (an action's whole body, a list item's notes), when it was unsaved.
    public var text: String?
    public var savedAt: Date

    public init(kind: Kind, path: String, title: String?, text: String?, savedAt: Date) {
        self.kind = kind
        self.path = path
        self.title = title
        self.text = text
        self.savedAt = savedAt
    }

    public var id: String { "\(kind.rawValue):\(path):\(savedAt.timeIntervalSince1970)" }
    public var note: NoteID { NoteID(path: path) }
    /// What the person would call the note: the typed title, else the file's.
    public var displayTitle: String { title ?? note.title }

    /// Everything typed, as one text to copy: the title on the first line when it was unsaved.
    public var copyText: String {
        [title, text].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// The command that writes this text into the note as it is now, or `nil` when the note is
    /// no longer where it was (renamed, completed or trashed since) — then only copying is left.
    /// Only the unsaved fields change; everything else stays as the vault has it.
    public func restoreCommand(in snapshot: VaultSnapshot) -> GTDCommand? {
        switch kind {
        case .action:
            guard var action = snapshot.action(note) else { return nil }
            if let title { action.title = title }
            if let text { action.body = text }
            return .updateAction(action)
        case .listItem:
            guard let item = snapshot.listItem(note) else { return nil }
            return .updateListItem(note, title: title ?? item.title, notes: text ?? item.notes)
        }
    }
}

/// Where the journal lives. The app's is a JSON file in Application Support
/// (`GTDServices.FileUnsavedTextStore`); tests and previews keep it in memory.
public protocol UnsavedTextStore: Sendable {
    func load() throws -> [UnsavedText]
    func save(_ entries: [UnsavedText]) throws
}

public final class InMemoryUnsavedTextStore: UnsavedTextStore, @unchecked Sendable {
    // Main-actor use only (the journal is `@MainActor`); `@unchecked` for the protocol.
    public private(set) var entries: [UnsavedText]
    public private(set) var saves = 0

    public init(_ entries: [UnsavedText] = []) { self.entries = entries }

    public func load() throws -> [UnsavedText] { entries }
    public func save(_ entries: [UnsavedText]) throws {
        self.entries = entries
        saves += 1
    }
}

/// The crash-safe copy of held edits (#56). One per app run, handed to every `AppModel`.
///
/// On creation it reads what the last run left behind into `recovered`: text that never
/// reached the vault — the app crashed, or a save was refused and the app quit. Those entries
/// stay in the file until the person restores or discards them. The editors' current unsaved
/// text (`update(live:)`) is written next to them a moment after typing pauses, and at once when
/// the shell flushes before quitting, so a clean quit leaves nothing behind.
@MainActor
@Observable
public final class UnsavedTextJournal {
    /// Left by an earlier run, waiting for Restore or Discard.
    public private(set) var recovered: [UnsavedText]
    /// Set when the journal file could not be read or written; the shell shows it once.
    public private(set) var failure: String?

    @ObservationIgnored private let store: any UnsavedTextStore
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var live: [UnsavedText] = []
    @ObservationIgnored private var written: [UnsavedText]
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(store: any UnsavedTextStore, delay: Duration = .milliseconds(400)) {
        self.store = store
        self.delay = delay
        var loaded: [UnsavedText] = []
        var failure: String?
        do {
            loaded = try store.load()
        } catch {
            failure = String(describing: error)
        }
        recovered = loaded
        written = loaded
        self.failure = failure
    }

    /// The editors' unsaved text right now. Written after `delay`; a newer call restarts it.
    public func update(live entries: [UnsavedText]) {
        guard entries != live else { return }
        live = entries
        pending?.cancel()
        let delay = self.delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    /// Writes what is pending at once (the shell's flush before quitting).
    public func writeNow() {
        pending?.cancel()
        pending = nil
        let entries = recovered + live
        guard entries != written else { return }
        do {
            try store.save(entries)
            written = entries
        } catch {
            failure = String(describing: error)
        }
    }

    /// Restored or discarded: the entry leaves the journal for good.
    public func resolve(_ entry: UnsavedText) {
        recovered.removeAll { $0 == entry }
        writeNow()
    }

    public func clearFailure() { failure = nil }
}
