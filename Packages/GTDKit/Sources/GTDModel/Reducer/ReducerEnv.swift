import Foundation

/// Everything the reducer needs from the outside world. Passing it in keeps `Reducer.reduce`
/// pure and deterministic: same snapshot + same command + same env ⇒ equal `Reduction`.
public struct ReducerEnv: Sendable {
    public var now: Date
    public var today: Day
    /// Stable per-device id; goes into the routine-log file name (N3).
    public var deviceID: String
    public var calendar: Calendar

    public init(now: Date, today: Day, deviceID: String, calendar: Calendar = .current) {
        self.now = now
        self.today = today
        self.deviceID = deviceID
        self.calendar = calendar
    }

    /// Env for "right now" on this device.
    public static func live(deviceID: String, calendar: Calendar = .current) -> ReducerEnv {
        let now = Date()
        return ReducerEnv(now: now, today: Day(now, calendar: calendar), deviceID: deviceID, calendar: calendar)
    }
}

/// The result of one command: the new snapshot, anything the shell should present, and file
/// effects that the snapshot diff cannot express (knowledge notes, trash and archive moves,
/// the weekly review note).
/// `renames` is what tells "this note is gone" apart from "this note is called something else
/// now": a note whose `NoteID` the command changed appears there, so navigation state pointing
/// at the old id can follow it instead of being dropped (`RenameMap`).
public struct Reduction: Sendable {
    public var snapshot: VaultSnapshot
    public var prompts: [AppPrompt]
    public var extraOps: [VaultFileOp]
    /// Notes that live in no snapshot collection and still have to be written: the Knowledge
    /// note a capture becomes (I4b). `GTDModel` never produces markdown (ARCHITECTURE §6), so it
    /// says *what the note says* and `GTDServices` encodes it — the same division as the weekly
    /// review note. Each one is written **after** `extraOps`, so a note that moves into place
    /// first is then patched where it lands.
    public var filedNotes: [FiledNote]
    public var renames: RenameMap

    public init(
        snapshot: VaultSnapshot,
        prompts: [AppPrompt] = [],
        extraOps: [VaultFileOp] = [],
        filedNotes: [FiledNote] = [],
        renames: RenameMap = .empty
    ) {
        self.snapshot = snapshot
        self.prompts = prompts
        self.extraOps = extraOps
        self.filedNotes = filedNotes
        self.renames = renames
    }
}

/// One note the reducer files outside every snapshot collection — today only the Knowledge note
/// an inbox capture becomes (I4b). It is the leanest note in the vault: an optional `created`
/// stamp and a free body, exactly like a capture, which is what it used to be.
///
/// `source` is the note's own text as it was read, so unknown frontmatter keys survive the
/// filing; `body` replaces the body outright, so what ends up on disk is what the reducer
/// decided and never a stale copy of the capture.
public struct FiledNote: Sendable, Equatable {
    public var id: NoteID
    public var body: String
    /// The capture's own timestamp — the note is the same note, so it keeps its age (C3).
    public var created: Date
    public var source: NotePassthrough

    public init(id: NoteID, body: String, created: Date, source: NotePassthrough = .empty) {
        self.id = id
        self.body = body
        self.created = created
        self.source = source
    }
}
