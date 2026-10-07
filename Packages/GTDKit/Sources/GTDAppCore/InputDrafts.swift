import Foundation
import Observation
import GTDModel

/// #94 — what a dialog holds that has no place in the vault yet, kept so that leaving the dialog
/// never loses it.
///
/// #85 writes a half-processed inbox card into its own note. Most other dialogs have nowhere to
/// write to before their main button is pressed: the name of a project that does not exist yet,
/// a waiting `who` the follow-up sheet has not set, action fields typed over a list item (L1
/// gives a list item only its notes), the "What's next?" line. Inventing vault fields for those
/// would be new schema, so they are kept here instead — a small device-local store beside the
/// crash journal (`GTDServices.FileInputDraftStore`), never in the vault — and **the same dialog
/// restores them when it opens again** for the same note.
///
/// The rule every dialog follows (user decision, #94):
/// - typing keeps the draft (`keep`), written to disk a moment after typing pauses and at once
///   when the app is about to stop (`AppModel.flushHeldEdits`), so `Esc`, a swipe, a click
///   outside, ⌘Q, backgrounding, a closed window and a crash all leave it there;
/// - the dialog's main button clears it once what it sent went through (`clear`);
/// - an explicit **Cancel** clears it — the one deliberate discard.
///
/// Values are any `Codable` type, stored as JSON under a key from `InputDraftKey`.
public struct InputDraft: Codable, Sendable, Equatable {
    /// The value, JSON-encoded.
    public var json: String
    public var savedAt: Date

    public init(json: String, savedAt: Date) {
        self.json = json
        self.savedAt = savedAt
    }
}

/// Where the drafts live. The app's is a JSON file in Application Support
/// (`GTDServices.FileInputDraftStore`); tests and previews keep them in memory.
public protocol InputDraftStore: Sendable {
    func load() throws -> [String: InputDraft]
    func save(_ drafts: [String: InputDraft]) throws
}

public final class InMemoryInputDraftStore: InputDraftStore, @unchecked Sendable {
    // Main-actor use only (`InputDrafts` is `@MainActor`); `@unchecked` for the protocol.
    public private(set) var drafts: [String: InputDraft]
    public private(set) var saves = 0

    public init(_ drafts: [String: InputDraft] = [:]) { self.drafts = drafts }

    public func load() throws -> [String: InputDraft] { drafts }
    public func save(_ drafts: [String: InputDraft]) throws {
        self.drafts = drafts
        saves += 1
    }
}

/// The drafts of every dialog, one per app run, handed to every `AppModel` by the shell.
@MainActor
@Observable
public final class InputDrafts {
    /// Set when the file could not be read or written; the shell shows it once. The drafts in
    /// memory still work.
    public private(set) var failure: String?

    @ObservationIgnored private let store: any InputDraftStore
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var drafts: [String: InputDraft]
    @ObservationIgnored private var written: [String: InputDraft]
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(
        store: any InputDraftStore = InMemoryInputDraftStore(),
        delay: Duration = .milliseconds(400),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.delay = delay
        self.now = now
        var loaded: [String: InputDraft] = [:]
        do {
            loaded = try store.load()
        } catch {
            failure = String(describing: error)
        }
        drafts = loaded
        written = loaded
    }

    /// The draft kept under `key`, or `nil` when there is none (or it no longer decodes as
    /// `type` — then it stays in the store untouched rather than being dropped).
    public func value<Value: Decodable>(_ type: Value.Type, for key: String) -> Value? {
        guard let draft = drafts[key], let data = draft.json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func hasDraft(for key: String) -> Bool { drafts[key] != nil }

    /// Keeps `value` under `key`; `nil` clears it. Written after `delay`.
    public func keep<Value: Encodable>(_ value: Value?, for key: String) {
        guard let value else {
            clear(key)
            return
        }
        guard let data = try? Self.encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        guard drafts[key]?.json != json else { return }
        drafts[key] = InputDraft(json: json, savedAt: now())
        scheduleWrite()
    }

    /// The dialog's main button went through, or its `Cancel` was pressed.
    public func clear(_ key: String) {
        guard drafts.removeValue(forKey: key) != nil else { return }
        scheduleWrite()
    }

    /// Writes what is pending at once (the shell's flush before quitting).
    public func writeNow() {
        pending?.cancel()
        pending = nil
        guard drafts != written else { return }
        do {
            try store.save(drafts)
            written = drafts
        } catch {
            failure = String(describing: error)
        }
    }

    public func clearFailure() { failure = nil }

    /// True when `text` holds nothing worth keeping.
    public nonisolated static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleWrite() {
        pending?.cancel()
        let delay = self.delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// The key each dialog keeps its draft under. A key names the dialog and, where the dialog is
/// about one note, that note's vault path — so a sheet reopened over the same note finds it,
/// and one over another note starts empty.
public enum InputDraftKey {
    /// The follow-up sheet (W1) opened for `note` — an inbox card, an action, or a "Make
    /// action" card (then `note` is that card's own key).
    public static func waiting(_ owner: String) -> String { "waiting:" + owner }
    public static func waiting(_ note: NoteID) -> String { waiting(note.path) }
    /// The `Defer to review` reason (I5) of an inbox card.
    public static func deferReason(_ note: NoteID) -> String { "deferReason:" + note.path }
    /// `New list…` in the list picker (inbox `More…`, a drop onto Lists).
    public static let newListInPicker = "listPicker.newList"
    /// `New folder` in the inbox's Knowledge sheet.
    public static let newKnowledgeFolder = "knowledge.newFolder"
    /// The "Make action" card over a list item (L4).
    public static func makeActionOverListItem(_ item: NoteID) -> String {
        "makeAction.listItem:" + item.path
    }
    /// The "Make action" card over a project step (P6). The step's text, not its index, so a
    /// reordered list still finds it.
    public static func makeActionOverStep(project: NoteID, text: String) -> String {
        "makeAction.step:" + project.path + "\n" + text
    }
    /// The "Make action" card over a line typed into "What's next?" (P5).
    public static func makeActionOverWhatsNext(project: NoteID, title: String) -> String {
        "makeAction.whatsNext:" + project.path + "\n" + title
    }
    /// The new-project sheet (E4).
    public static let newProject = "newProject"
    /// "Turn into project" (A2) for `action`.
    public static func convertToProject(_ action: NoteID) -> String { "convertToProject:" + action.path }
    /// The free-text line of "What's next?" (P5) for `project`.
    public static func whatsNext(_ project: NoteID) -> String { "whatsNext:" + project.path }
    /// The project detail's `New step` field.
    public static func newStep(_ project: NoteID) -> String { "newStep:" + project.path }
    /// The weekly review's card over a deferred inbox item.
    public static func reviewDeferred(_ item: NoteID) -> String { "review.deferred:" + item.path }
    /// Settings: `Add a context`, `Add a list`, and the two renames (by the old name).
    public static let settingsNewContext = "settings.newContext"
    public static let settingsNewList = "settings.newList"
    public static func settingsRenameContext(_ old: String) -> String { "settings.renameContext:" + old }
    public static func settingsRenameList(_ old: String) -> String { "settings.renameList:" + old }
    /// Onboarding's name for a new vault (#60).
    public static let newVaultName = "onboarding.newVaultName"
}

/// #94 — the follow-up sheet's two values while it is open.
public struct WaitingSheetDraft: Codable, Sendable, Equatable {
    public var who: String
    public var followUp: Day?

    public init(who: String = "", followUp: Day? = nil) {
        self.who = who
        self.followUp = followUp
    }

    /// Nothing typed and no date chosen.
    public var isEmpty: Bool { InputDrafts.isBlank(who) && followUp == nil }
}
